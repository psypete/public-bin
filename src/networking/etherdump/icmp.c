#include <stdio.h>
#include <string.h>
#include <time.h>
#ifndef __CYGWIN__
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netpacket/packet.h>
#endif
#include "etherdump.h"


int process_icmp_packet( struct ip_packet *ip, struct icmp_hdr *icmp, struct icmp_packet *packet ) {

    packet->type = (ntohs(icmp->type) >> 8);
    packet->code = (ntohs(icmp->code) >> 8);
    packet->id = ntohs(icmp->id);
    packet->seq = ntohs(icmp->sequence);
    packet->length = ( ip->packet_length - ip->header_length );

    packet->start = icmp;
    packet->end = (void *) ((void *) icmp + 8); // the default icmp header length for our default header (type, code, checksum, id, sequence)

    return( 0 );
}


int tcpdump_print_icmp(struct ip_packet *packet_ip, struct icmp_packet *packet_icmp) {
    struct ip_packet tmp_packet_ip;

    fprintf(F_logfd, "%02d:%02d:%02d.%d IP %s > %s: ICMP", lt->tm_hour, lt->tm_min, lt->tm_sec, (int)tv.tv_usec, packet_ip->source_a, packet_ip->destination_a);

    switch ( packet_icmp->type ) {
        case 8:
            fprintf(F_logfd, " echo request, id %hi, seq %hi, length %hi", packet_icmp->id, packet_icmp->seq, packet_icmp->length);
            break;

        case 0:
            fprintf(F_logfd, " echo reply, id %hi, seq %hi, length %hi", packet_icmp->id, packet_icmp->seq, packet_icmp->length);
            break;

        // the following cases can have an ip packet as payload:
        //  type 3 code 0-5, type 11 code 0,1, type 12 code 0, type 4 code 0, type 5 code 0-3
        // (fall through the cases here until the break)
        case 3:
        case 11:
        case 12:
        case 4:
        case 5:
            // decode the IP packet returned in the icmp payload
            process_ip_packet( (struct ip_hdr *) packet_icmp->end, &tmp_packet_ip );
            //printf("\nembedded packet: version %i src %s dst %s protocol %i\n", tmp_packet_ip.version, tmp_packet_ip.source_a, tmp_packet_ip.destination_a, tmp_packet_ip.protocol);

            if ( tmp_packet_ip.version == 4 ) { // just making sure there is an ipv4 packet here
                int port = 0;
                char proto[16];
                char buff[1024];

                if ( tmp_packet_ip.protocol == SOL_UDP ) { // has a udp packet in it
                    static struct udp_packet tmp_packet_udp;
                    process_udp_packet( &tmp_packet_ip, tmp_packet_ip.end, &tmp_packet_udp );
                    port = tmp_packet_udp.destination;
                    strncpy(proto, "udp", sizeof(proto));

                } else if ( tmp_packet_ip.protocol == SOL_TCP ) { // has a tcp packet in it
                    static struct tcp_packet tmp_packet_tcp;
                    process_tcp_packet( &tmp_packet_ip, tmp_packet_ip.end, &tmp_packet_tcp );
                    port = tmp_packet_tcp.destination;
                    strncpy(proto, "tcp", sizeof(proto));

                } else {
                    strncpy(proto, "(?)", sizeof(proto));

                }

                if ( packet_icmp->type == 3 ) {
                    if (packet_icmp->code == 3) {
                         snprintf(buff, sizeof(buff), " %s %s port %d unreachable, length %u", tmp_packet_ip.destination_a, proto, port, packet_icmp->length);
                    } else if ( packet_icmp->code == 0 || packet_icmp->code == 1 || packet_icmp->code == 2 ) {
                        snprintf(buff, sizeof(buff), " %s %s unreachable, length %u", tmp_packet_ip.destination_a, proto, packet_icmp->length);
                    }

                } else if ( packet_icmp->type == 11 ) {
                    snprintf(buff, sizeof(buff), " %s time exceeded, length %u", tmp_packet_ip.destination_a, packet_icmp->length);

                } else if ( packet_icmp->type == 12 ) {
                    snprintf(buff, sizeof(buff), " %s parameter problem, length %u", tmp_packet_ip.destination_a, packet_icmp->length);

                } else if ( packet_icmp->type == 4 ) {
                    snprintf(buff, sizeof(buff), " %s %s port %i source quench, length %u", tmp_packet_ip.destination_a, proto, port, packet_icmp->length);

                } else if ( packet_icmp->type == 5 ) {
                    // convert id, sequence to gateway address
                    // NOTE: i have not tested this on the wire, but this 'should' work.
                    // convert the values that are in host byte order back to network byte and
                    // stuff them into a 32 bit data structure in the correct order.
                    uint16_t id = htons(packet_icmp->id), seq = htons(packet_icmp->seq);
                    struct in_addr gw_addr;

                    gw_addr.s_addr = (uint32_t) ( (uint32_t) (id << 16) | (uint32_t) (seq) );
                    snprintf(buff, sizeof(buff), " %s %s port %i redirect to %s, length %u", tmp_packet_ip.destination_a, proto, port, inet_ntoa(gw_addr), packet_icmp->length);
                }

                fprintf(F_logfd, buff);

                break;
            }

            // note that this is commented out on purpose! if the ipv4 test above failed,
            // we want to fall down into 'default' to print out the type/code.

        default:
            fprintf(F_logfd, " unknown type %i code %i", packet_icmp->type, packet_icmp->code);
            break;
    }

    return( 0 );
}


