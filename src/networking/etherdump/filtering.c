#include <stdio.h>
#include <string.h>
#include <time.h>
#ifndef __CYGWIN__
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netpacket/packet.h>
#endif
#include <stdlib.h>
#include "etherdump.h"



int filter_packet( struct my_sockaddr_ll *from, void *main_packet, void *packet, struct packet_filter_rule *filters, int filter_idx ) {

    int i, j, bad_filter=0;
    struct ip_packet *ip;
#ifdef USE_TCP
    struct tcp_packet *tcppkt;
#endif
#ifdef USE_UDP
    struct udp_packet *udppkt;
#endif
#ifdef USE_ICMP
    struct icmp_packet *icmppkt;
#endif
#ifdef USE_ARP
    struct arp_packet *arp;
#endif
    int source_port=0, destination_port=0, tmp_i, protocol;
    unsigned char src_match, dst_match, not=0;
    //char src[16], dst[16];
    unsigned char *src, *dst;
    uint16_t ethertype;
    int *pintbuff;

    ethertype = ntohs(from->sll_protocol);
    if ( ethertype == ETH_P_IP ) {
        ip = (struct ip_packet *) main_packet;
        src = ip->source_a;
        dst = ip->destination_a;
        protocol = ip->protocol;

        #ifdef USE_TCP
            if ( ip->protocol == SOL_TCP ) {
                tcppkt = (struct tcp_packet *) packet;
                source_port = tcppkt->source;
                destination_port = tcppkt->destination;
            }
        #endif
        #ifdef USE_UDP
            if ( ip->protocol == SOL_UDP ) {
                udppkt = (struct udp_packet *) packet;
                source_port = udppkt->source;
                destination_port = udppkt->destination;
            }
        #endif
        #ifdef USE_ICMP
            if ( ip->protocol == SOL_ICMP ) {
                icmppkt = (struct icmp_packet *) packet;
            }
        #endif

    } else if ( ethertype == ETH_P_ARP ) {
        arp = (struct arp_packet *) main_packet;
        src = arp->sender_protoaddr;
        dst = arp->target_protoaddr;
        protocol = ethertype;
    }

    for ( i=0; i<filter_idx; i++ ) {

        if ( (filters[i].match_type & FILTER_SET_NOT) == FILTER_SET_NOT ) {
            not = 1;
        } else {
            not = 0;
        }

        // check if the last filter had AND set. if it was bad, the packet failed the filter
        if ( (i > 0) && ((filters[i-1].match_type & FILTER_SET_AND) == FILTER_SET_AND) && (bad_filter) ) {
            if ( FILTDEBUG ) fprintf(stderr, "AND failed; breaking\n");
            break;
        }

        // check if the last filter had OR set. if it was good, we can skip this filter
        if ( (i > 0) && ((filters[i-1].match_type & FILTER_SET_OR) == FILTER_SET_OR) ) {
            if ( bad_filter ) {
                if ( FILTDEBUG ) fprintf(stderr, "last filter was bad but OR was set; continuing\n");
                bad_filter = 0;
                //continue;
            } else if ( ! bad_filter ) {
                if ( FILTDEBUG ) fprintf(stderr, "last filter was good and OR was set, so breaking now\n");
                break;
            }
        }

        // otherwise, if we had a bad_filter set, break now
        if ( bad_filter ) {
            break;
        }

        pintbuff = (int *) filters[i].buff;

        // check protocol
        if ( (filters[i].match_type & FILTER_SET_PROTOCOL) == FILTER_SET_PROTOCOL ) {

            int good = 0;
            int *protocols[] = {
                &filters[i].proto,
                NULL,
                NULL
            };

            // determine if we need to check .buff for a protocol (if HOST or PORT has been set, this won't be a protocol)
            if (
                    (filters[i].buff != NULL) &&
                    ((filters[i].match_type & FILTER_SET_PORT) != FILTER_SET_PORT) &&
                    ((filters[i].match_type & FILTER_SET_HOST) != FILTER_SET_HOST)
            ) {
                //protocols[1] = &filters[i].buff;
                protocols[1] = filters[i].buff;
            }

            for ( j=0; j<2; j++ ) {

                tmp_i = 0;

                if ( protocols[j] == NULL )
                    break;

                tmp_i = *protocols[j];
                if ( tmp_i < 0 )
                    tmp_i = *protocols[j] * -1;
                
                //if ( memcmp( &tmp_i, &protocol, sizeof(int) ) == 0 ) {
                if ( tmp_i == protocol )
                    good = 1;

                //if ( memcmp( &tmp_i, &ethertype, sizeof(int) ) == 0 ) {
                if ( tmp_i == ethertype )
                    good = 1;

            }

            if ( not ) {
                if ( good ) {
                    good--;
                } else {
                    good++;
                }
            }

            if ( !good) {
                //pintbuff = (int *) filters[i].buff;
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: protocol %i/ethertype %i does not match filter protocol %i/buff %i\n", i, protocol, ethertype, filters[i].proto, *pintbuff);
                bad_filter++;
                continue;
            } else {
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: protocol matched %i\n", i, tmp_i);
            }

        }

        // check the host
        if ( (filters[i].match_type & FILTER_SET_HOST) == FILTER_SET_HOST ) {

            int good=0;

            // what the hell? .buff should have been set if HOST was set
            if ( filters[i].buff == NULL && (!not) ) {
                fprintf(stderr, "error: filter %i: buff wasn't set\n", i);
                bad_filter++;
                continue;
            }

            src_match = strncmp( (const char *) src, filters[i].buff, strlen((const char *) src) );
            dst_match = strncmp( (const char *) dst, filters[i].buff, strlen((const char *) dst) );

            //if ( src_match != 0 && (filters[i].match_type & FILTER_SET_SOURCE) == FILTER_SET_SOURCE && (!not) ) {
            if ( src_match != 0 && (filters[i].match_type & FILTER_SET_SOURCE) == FILTER_SET_SOURCE ) {
                //if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: src host %s does not match filter src host %s\n", i, src, filters[i].buff);
                //bad_filter++;
                //continue;
                good=0;
            //} else if ( dst_match != 0 && (filters[i].match_type & FILTER_SET_DESTINATION) == FILTER_SET_DESTINATION && (!not) ) {
            } else if ( dst_match != 0 && (filters[i].match_type & FILTER_SET_DESTINATION) == FILTER_SET_DESTINATION ) {
                //if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: dst host %s does not match filter dst host %s\n", i, dst, filters[i].buff);
                //bad_filter++;
                //continue;
                good=0;
            } else if ( src_match == 0 || dst_match == 0 ) {
                good=1;
            }

            // now check ether hw address
            // TODO: change packet socket to RAW so we can see the link layer addresses
            //src_match = strncmp(

            if ( not ) {
                if ( good ) {
                    good--;
                } else {
                    good++;
                }
            }

            if ( good == 0 ) {
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: src host %s and dst host %s do not match filter host %s\n", i, src, dst, filters[i].buff);
                bad_filter++;
                continue;
            } else {
                if ( FILTDEBUG ) fprintf(stderr, "info: fitler %i: host matched %s\n", i, filters[i].buff);
            }

        }

        // check the port
        if ( (filters[i].match_type & FILTER_SET_PORT) == FILTER_SET_PORT ) {
            
            int good=0;

            // wtf
            if ( filters[i].buff == NULL ) {
                fprintf(stderr, "error: filter %i: buff wasn't set\n", i);
                bad_filter++;
                continue;
            }

            src_match = memcmp( &source_port, (int *) filters[i].buff, sizeof(source_port) );
            dst_match = memcmp( &destination_port, (int *) filters[i].buff, sizeof(destination_port) );

            //if ( src_match != 0 && (filters[i].match_type & FILTER_SET_SOURCE) == FILTER_SET_SOURCE && (!not) ) {
            if ( src_match != 0 && (filters[i].match_type & FILTER_SET_SOURCE) == FILTER_SET_SOURCE ) {
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: src port %i does not match filter src port %i\n", i, source_port, *pintbuff);
                //bad_filter++;
                //continue;
                good=0;
            //} else if ( dst_match != 0 && (filters[i].match_type & FILTER_SET_DESTINATION) == FILTER_SET_DESTINATION && (!not) ) {
            } else if ( dst_match != 0 && (filters[i].match_type & FILTER_SET_DESTINATION) == FILTER_SET_DESTINATION ) {
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: dst port %i does not match filter dst port %i\n", i, destination_port, *pintbuff);
                //bad_filter++;
                //continue;
                good=0;
            } else if ( src_match == 0 || dst_match == 0 ) {
                good=1;
            }

            // this makes the match implicitly good if the protocol is not a match and we have the
            // 'not' filter applied to it (essentially, this filter rule is good every time the protocol
            // is not a match)
            if ( not ) {
                if ( good ) {
                    good--;
                } else {
                    good++;
                }
            }

            if ( good == 0 ) {
                if ( FILTDEBUG ) fprintf(stderr, "info: filter %i: src port %i and dst port %i do not match filter port %i\n", i, source_port, destination_port, *pintbuff);
                bad_filter++;
                continue;
            } else {
                if ( FILTDEBUG ) fprintf(stderr, "info: fitler %i: port matched %i\n", i, *pintbuff);
            }
        }

    }

    return (bad_filter);
}


/*
 * so, here we parse each argv for space-delimited and parenthesis-delimited sets of keywords and arguments.
 * we set a bitmask in p[idx].match_type for each filter rule. there can be multiple bits set, so we can do
 * things like have a rule which matches 'not proto tcp' or 'src host google.com'.
 * when we get an 'and', 'or', or a parenthesis we skip to the next filter, though 'and' and 'or' get set in
 * the filter preceeding the rest of the arguments.
 */

int parse_filter(int argc, char **argv, int i, struct packet_filter_rule *p) {

    struct protoent *pf_proto;

    char *ptr, *token;
    char *saveptr;

    int j, num, tmp_i, idx=0;

    int *pintbuff;

    for ( ; i<argc; i++ ) {

        if ( debug ) fprintf(stderr, "parse_filter(%i) = \"%s\"\n", i, argv[i]);

        for ( ptr = strdup(argv[i]); (token=strtok_r(ptr," ",&saveptr)) != NULL; ptr = NULL ) {
            if ( debug ) fprintf(stderr, "  token: \"%s\"\n", token);

            num = 0;
            for ( j=0; filter_bit_map[j].name != NULL; j++ ) {
                if ( strncmp(filter_bit_map[j].name, token, strlen(token)) == 0 ) {
                    num = filter_bit_map[j].val;
                    break;
                }
            }

            // set the bit mask for this word if it was found in filter_bit_map list
            if ( num ) {
                if ( debug ) fprintf(stderr, "    filter %i: setting filter \"%s\" (%i)\n", idx, filter_bit_map[j].name, filter_bit_map[j].val);
                p[idx].match_type |= num;
            }

            // now we do the extra work of handling the words' arguments and such
            switch ( num ) {
                case FILTER_SET_NOT:
                case FILTER_SET_SOURCE:
                case FILTER_SET_DESTINATION:
                    // ignore these flags; they've been set in match_type bitmask above
                    break;

                case FILTER_SET_AND:
                case FILTER_SET_OR:
                    // here we skip to the next filter if we got an 'and' or 'or'.
                    idx++;
                    break;

                case FILTER_SET_PROTOCOL:
                    // if 'ip proto tcp', set proto to ETH_P_IP and buff to SOL_TCP.
                    // if 'ether proto ip', set proto to -1 and buff to ETH_P_IP.
                    // if 'tcp', set buff to SOL_TCP.
                    // if 'arp src foo', set proto to ETH_P_ARP * -1 and later set buff to "foo".
                    // if 'tcp port 21', set proto to SOL_TCP and buff to 21.
                    // if 'ether src foo', set proto to ETH_P_IP * -1 and buff to "foo".
                    //
                    // ok. so if we have found a 'proto' token, anything that follows it must go into 'buff'.
                    // if we don't have a 'proto' token, it must go into 'proto'.
                    // in this way 'ether proto ip' puts 'ether' (-1) into proto and '0'
                    //
                    // for cases like 'tcp', where nothing else is specified, normally only p[idx].proto is
                    // set and p[idx].buff remains untouched. p[idx].buff will be NULL until something set it,
                    // so if this is still NULL at packet checking time, just use p[idx].buff to check the protocol.

                    // so if we found the 'proto' keyword it means that p[idx].proto was already set and we
                    // need to put the following protocol value into p[idx].buff, thus setting 'j' or not.
                    // pcap-filter only allows it in such forms like 'ip proto tcp', 'ether proto ip', etc
                    j = 0;
                    if ( (strcmp(token,"proto")==0) || (strcmp(token,"protocol")==0) ) {
                        ptr = NULL;
                        if ( (token=strtok_r(ptr," ",&saveptr)) == NULL )
                            show_usage("missing protocol argument");
                        j = 1;
                    }

                    // note that i put 'arp', 'ip' and 'ether' into my list of hardcoded protocols for this to work.
                    // since arp and ip aren't "ip protocols" this would normally fail (and 'ip' would probably
                    // be resolved as 'protocol 0' instead of 0x0800, the ethertype)
                    pf_proto = my_getprotobyname(token);

                    if (pf_proto->p_name == NULL) {
                        if (debug) fprintf(stderr, "      error: no proto %s found\n", token);
                        break;
                    }// else { printf("proto name %s\n", pf_proto->p_name); }

                    if ( j == 0 ) {
                        if (debug) fprintf(stderr, "      setting proto %i\n", pf_proto->p_proto);
                        p[idx].proto = pf_proto->p_proto;
                    } else {
                        if (debug) fprintf(stderr, "      setting buff %i from token %s (idx %i)\n", pf_proto->p_proto, token, idx);
                        if ( p[idx].buff != NULL )
                            free(p[idx].buff);

                        p[idx].buff = (int *) safe_malloc( sizeof(int) );
                        pintbuff = (int *) p[idx].buff;
                        memmove( pintbuff, &pf_proto->p_proto, sizeof(int) );
                        //*pintbuff = pf_proto->p_proto;

                        //idx++; // if j==1, we saw 'proto ' already, so this filter is done
                        
                        // but then again, this should naturally get updated in the next loop
                        // run to properly support 'and', 'or', etc.
                    }
                    break;

                case FILTER_SET_PORT:
                    ptr = NULL;
                    if ( (token=strtok_r(ptr," ",&saveptr)) == NULL )
                        show_usage("missing port argument");

                    tmp_i = atoi(token);
                    if ( debug ) fprintf(stderr, "      setting buff %i\n", tmp_i);
                    if ( p[idx].buff != NULL )
                        free(p[idx].buff);
                    p[idx].buff = (int *) safe_malloc( sizeof(tmp_i) );
                    pintbuff = (int *) p[idx].buff;
                    memmove(pintbuff, &tmp_i, sizeof(tmp_i));
                    break;

                case FILTER_SET_HOST:
                    ptr = NULL;
                    if ( (token=strtok_r(ptr," ",&saveptr)) == NULL )
                        show_usage("missing host argument");

                    if ( debug ) fprintf(stderr, "      setting buff \"%s\"\n", token);
                    tmp_i = strlen(token)+1;

                    if ( p[idx].buff != NULL )
                        free(p[idx].buff);
                    p[idx].buff = (unsigned char *) safe_malloc( sizeof(unsigned char) * (tmp_i) );

                    strncpy(p[idx].buff, token, tmp_i-1);
                    //memmove(&p[idx].buff, token, tmp_i);
                    break;

                default:
                    // great, now we get to decide wtf somebody wanted to pass.
                    // for now just shove whatever it is into buff of the current filter.
                    if ( debug ) fprintf(stderr, "      setting p[%i]->buff \"%s\" (match_type %i)\n", idx, token, p[idx].match_type);
                    tmp_i = strlen(token) + 1;
                    if ( p[idx].buff != NULL ) {
                        free(p[idx].buff);
                    }
                    p[idx].buff = (unsigned char *) safe_malloc( sizeof(unsigned char) * (tmp_i) );
                    memmove(p[idx].buff, token, tmp_i);

                    break;

            };

        }

        // i'm gonna go ahead and assume each new argument is a new filter rule
        idx++;
    }

    return(idx);
}


