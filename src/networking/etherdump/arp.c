#include <stdio.h>
#include <string.h>
#include <time.h>
#ifndef __CYGWIN__
#include <sys/time.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netpacket/packet.h>
#endif
#include "etherdump.h"



int process_arp_packet( struct arp_hdr *arp, struct arp_packet *packet ) {

    int pkt_siz = ( sizeof(arp->hw_type) + sizeof(arp->proto) + sizeof(arp->hw_len) + sizeof(arp->proto_len) + sizeof(arp->operation) );
    struct in_addr tmpaddr;

    packet->hardware_type = ntohs(arp->hw_type);
    packet->protocol = ntohs(arp->proto);
    packet->hardware_length = ( ntohs(arp->hw_len) >> 8 ) & 0x0F;
    packet->protocol_length = ( ntohs(arp->proto_len) >> 8 ) & 0x0F;
    packet->operation = ntohs(arp->operation);

    packet->header_length = ( pkt_siz + packet->hardware_length + packet->protocol_length + packet->hardware_length +packet->protocol_length );
    packet->packet_length = packet->header_length;

    memmove( &packet->sender_hw_address, ((unsigned char *) arp + pkt_siz), packet->hardware_length );
    packet->sender_proto_address = unsignedIntToLong( (unsigned char *) arp + pkt_siz + packet->hardware_length );

    memmove( &packet->target_hw_address, ((unsigned char *) arp + pkt_siz + packet->hardware_length + packet->protocol_length), packet->hardware_length );
    packet->target_proto_address = unsignedIntToLong( (unsigned char *) arp + pkt_siz + packet->hardware_length + packet->protocol_length + packet->hardware_length );

    //memset(&packet->sender_hwaddr, '\0', sizeof(packet->sender_hwaddr));
    //memset(&packet->target_hwaddr, '\0', sizeof(packet->sender_hwaddr));

    snprintf(packet->sender_hwaddr, sizeof(packet->sender_hwaddr), "%02X:%02X:%02X:%02X:%02X:%02X", packet->sender_hw_address[0], packet->sender_hw_address[1], packet->sender_hw_address[2], packet->sender_hw_address[3], packet->sender_hw_address[4], packet->sender_hw_address[5]);
    snprintf(packet->target_hwaddr, sizeof(packet->target_hwaddr), "%02X:%02X:%02X:%02X:%02X:%02X", packet->target_hw_address[0], packet->target_hw_address[1], packet->target_hw_address[2], packet->target_hw_address[3], packet->target_hw_address[4], packet->target_hw_address[5]);

    tmpaddr.s_addr = packet->sender_proto_address;
    strncpy(packet->sender_protoaddr, inet_ntoa(tmpaddr), sizeof(packet->sender_protoaddr));
    tmpaddr.s_addr = packet->target_proto_address;
    strncpy(packet->target_protoaddr, inet_ntoa(tmpaddr), sizeof(packet->target_protoaddr));

    //fprintf(F_logfd, "ARP:\n  hwtype %hu\n  protocol %hu\n  hwlen %i\n  protolen %i\n  operation %hu\n  sender_hwaddr %s\n  sender_protoaddr %s\n  target_hwaddr %s\n  target_protoaddr %s\n", packet->hardware_type, packet->protocol, packet->hardware_length, packet->protocol_length, packet->operation, packet->sender_hwaddr, packet->sender_protoaddr, packet->target_hwaddr, packet->target_protoaddr);

    packet->start = arp;
    packet->end = ( (unsigned char *) arp + pkt_siz + packet->hardware_length + packet->protocol_length + packet->hardware_length + packet->protocol_length );

    return( 0 );
}


int process_arp(unsigned char *buffer, int n, struct my_sockaddr_ll *from, struct packet_filter_rule *filters, int filter_idx) {

    int next_packet;
    struct arp_packet packet_arp;

    gettimeofday(&tv, NULL);
    lt = localtime( &tv.tv_sec );

    process_arp_packet( (struct arp_hdr *) buffer, &packet_arp );

    next_packet = filter_packet( from, &packet_arp, NULL, filters, filter_idx );

    if ( next_packet )
        return(0);

    fprintf(F_logfd, "%02d:%02d:%02d.%d ARP, ", lt->tm_hour, lt->tm_min, lt->tm_sec, (int)tv.tv_usec);

    if ( packet_arp.operation == 1 ) { // request
        fprintf(F_logfd, "Request who-has %s tell %s, length %i\n", packet_arp.target_protoaddr, packet_arp.sender_protoaddr, packet_arp.packet_length);
    } else if ( packet_arp.operation == 2 ) { // reply
        fprintf(F_logfd, "Reply %s is-at %s, length %i\n", packet_arp.sender_protoaddr, packet_arp.sender_hwaddr, packet_arp.packet_length);
    } else {
        fprintf(F_logfd, "unknown operation %i, sender %s, target %s\n", packet_arp.operation, packet_arp.sender_protoaddr, packet_arp.target_protoaddr);
    }

    return( 0 );
}

