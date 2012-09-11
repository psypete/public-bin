// etherdump.h

#include <stdio.h>

#ifdef __CYGWIN__
#include <winsock2.h>
#include <ws2tcpip.h> //IP_HDRINCL is here
#pragma comment(lib,"ws2_32.lib") //winsock 2.2 library
#else
#include <netpacket/packet.h>
#include <netdb.h>
#endif

#define RAW_SOCK_BUFSIZ 65536
#define FILTDEBUG (debug>5)


/*
 * (Stolen from the) Perl ARP Extension header file
 *
 * Programmed by Bastian Ballmann
 * Last update: 19.12.2003
 *
 * This program is free software; you can redistribute 
 * it and/or modify it under the terms of the 
 * GNU General Public License version 2 as published 
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will 
 * be useful, but WITHOUT ANY WARRANTY; without even 
 * the implied warranty of MERCHANTABILITY or FITNESS 
 * FOR A PARTICULAR PURPOSE. 
 * See the GNU General Public License for more details. 
 * */

#define ARPOP_REQUEST    1
#define ARPOP_REPLY      2
#define ARPOP_REVREQUEST 3
#define ARPOP_REVREPLY   4
#define ARPOP_INVREQUEST 8
#define ARPOP_INVREPLY   9
#define ARPHDR_ETHER     1

#ifndef ETH_ALEN
#define ETH_ALEN         6
#endif

#ifndef ETH_P_IP
#define ETH_P_IP         0x0800
#endif

#ifndef ETH_P_ARP
#define ETH_P_ARP        0x0806
#endif

#ifndef ETH_P_ALL
//#define ETH_P_ALL        0x0000
#define ETH_P_ALL        0x0003
#endif

#ifdef BSD
#define SOCK_TYPE        SOCK_RAW
#else
#define SOCK_TYPE        SOCK_PACKET
#endif
#define IP_ALEN          4

#ifndef SOL_TCP
#define SOL_TCP          6
#endif

#ifndef SOL_UDP
#define SOL_UDP          17
#endif

#ifndef SOL_ICMP
#define SOL_ICMP         1
#endif


// Add this for Cygwin environment compatibility


struct my_sockaddr_ll {
    unsigned short sll_family;   /* Always AF_PACKET */
    unsigned short sll_protocol; /* Physical layer protocol */
    int            sll_ifindex;  /* Interface number */
    unsigned short sll_hatype;   /* Header type */
    unsigned char  sll_pkttype;  /* Packet type */
    unsigned char  sll_halen;    /* Length of address */
    unsigned char  sll_addr[8];  /* Physical layer address */
};




#ifdef USE_FILTERING
struct filter_bits
{
  char *name;
  int val;
};

#define MAX_FILTERWORD_SIZE 32

// bitmask values for filter match_type
enum {
    FILTER_SET_NOT=1,
    FILTER_SET_AND=2,
    FILTER_SET_OR=4,
    FILTER_SET_PROTOCOL=8,
    FILTER_SET_SOURCE=16,
    FILTER_SET_DESTINATION=32,
    FILTER_SET_HOST=64,
    FILTER_SET_PORT=128
};

static const struct filter_bits filter_bit_map[] = {
      { "!", FILTER_SET_NOT },      { "not", FILTER_SET_NOT },
      { "and", FILTER_SET_AND },
      { "or", FILTER_SET_OR },
      { "proto", FILTER_SET_PROTOCOL },     //{ "protocol", FILTER_SET_PROTOCOL },
      { "src", FILTER_SET_SOURCE },         //{ "source", FILTER_SET_SOURCE },
      { "dst", FILTER_SET_DESTINATION },    //{ "dest", FILTER_SET_DESTINATION },
      { "host", FILTER_SET_HOST },
      { "port", FILTER_SET_PORT },
      // these are aliases which get handled specially in the filtering code
      { "ether", FILTER_SET_PROTOCOL }, { "ip", FILTER_SET_PROTOCOL }, { "tcp", FILTER_SET_PROTOCOL }, { "udp", FILTER_SET_PROTOCOL }, { "icmp", FILTER_SET_PROTOCOL }, { "arp", FILTER_SET_PROTOCOL },
      // THIS STRUCT MUST END WITH A NULL ENTRY OR WE GET AN ENDLESS LOOP!
      { NULL, 0 }
};


struct packet_filter_rule
{
  int match_type;
  int proto;                // this is used either for ethertype, network or transport layer
                            // protocol depending on if a 'type' or 'dir' is specified.
                            // if a protocol is specified it'll be put in 'buff' below and
                            // FILTER_SET_PROTO will be set. i haven't decided what will
                            // happen if you try to specify a different data link layer than
                            // ethernet; pretty much i'm going to assume 'proto' will be an
                            // ethertype unless FILTER_SET_PORT or another tcp or udp specific
                            // flag is set, in which case proto will be the tcp or udp proto
                            // number. pcap-filter(7) doesn't seem to support a way to match
                            // on both a type/dir and more than one protocol, so this should
                            // work for all uses of pcap-filter(7) style syntax.
                            // since i can't figure out a better method, if proto is negative
                            // it either means it's an ethernet data link layer or it's some
                            // other data link layer protocol (i can't find a list of numbers
                            // to signify this properly) and PROTO will probably be set with
                            // buff being the ethertype.
                            // also note that most useful ethertypes are well above the 255
                            // possible ip protocols, so if you ever have to figure out wtf
                            // a given thing is, do a size comparison. or something.
                            // for reference:
                            //   "ip src host 1.2.3.4" =
                            //      (match_type|=(SOURCE|HOST|PROTO),proto=0x0800,buff="1.2.3.4")
                            //   "not tcp dst port 21" =
                            //      (match_type|=(NOT|DESTINATION|PORT|PROTO),proto=6,buff=21)
                            //   "src port 80" =
                            //      (match_type|=(PORT),proto=0,buff=80)
                            //   "ip proto tcp" =
                            //      (match_type|=(PROTO),proto=0x0800,buff=6)
                            //   "ether proto ip" =
                            //      (match_type|=(PROTO),proto=-1,buff=0x0800)
                            //   "tcp" =
                            //      (match_type|=(PROTO),proto=6,buff=NULL)
                            //   "ip" =
                            //      (match_type|=(PROTO),proto=0x0800,buff=NULL)

  //unsigned char *buff;      // if match_type is not zero, this has been malloc'd!
  void *buff;      // if match_type is not zero, this has been malloc'd!
                            // remember to free it if you ever make match_type equal zero,
                            // or make match_type equal zero if you free it!
};
#endif


/*
 * the '*_hdr' structs are laid out exactly as the packets will come in, so *DONT MESS WITH THEM*.
 * the '*_packet' structs are the usable data structure form of the headers.
 */

#ifdef USE_ARP
// for ethernet ipv4 arp messages only
struct arp_hdr
{
  uint16_t hw_type;           /* 16 bits 0-15    - hardware type */
  uint16_t proto;             /* 16 bits 16-31   - protocol type */
  unsigned char hw_len;             /* 8 bits 32-39    - hardware address length */
  unsigned char proto_len;          /* 8 bits 40-47    - protocol address length */
  uint16_t operation;         /* 16 bits 48-63   - operation (1=request, 2=reply) */
//  unsigned char s_hwaddr_1, s_hwaddr_2, s_hwaddr_3, s_hwaddr_4, s_hwaddr_5, s_hwaddr_6;
//  //unsigned char s_hwaddr[6];    /* 48 bits 49-96   - sender hardware address */
//  uint32_t s_proto_addr;       /* 32 bits 97-128  - sender protocol address */
//  //unsigned char t_hwaddr[6];     /* 48 bits 129-176 - target hardware address */
//  unsigned char t_hwaddr_1, t_hwaddr_2, t_hwaddr_3, t_hwaddr_4, t_hwaddr_5, t_hwaddr_6;
//  uint32_t t_proto_addr;       /* 32 bits 177-208 - target protocol address */
};

struct arp_packet
{
  uint16_t hardware_type;
  uint16_t protocol;
  unsigned char hardware_length;
  unsigned char protocol_length;
  uint16_t operation;

  unsigned char header_length;
  unsigned char packet_length;

  // soooo yeah.... these should probably dynamically sized

  unsigned char sender_hw_address[6];
  char sender_hwaddr[18];
  uint32_t sender_proto_address;
  char sender_protoaddr[16];

  unsigned char target_hw_address[6];
  char target_hwaddr[18];
  uint32_t target_proto_address;
  char target_protoaddr[16];

  void *start;
  void *end;
};

int process_arp_packet( struct arp_hdr *arp, struct arp_packet *packet );
int process_arp(unsigned char *buffer, int n, struct my_sockaddr_ll *from, struct packet_filter_rule *p_filters, int p_filter_idx);
#endif


#ifdef USE_IP
struct ip_hdr
{
  unsigned char hlv;        /* +00 - version, header length */
  unsigned char tos;        /* +01 - dscp, ecn              */
  uint16_t tot_len;   /* +02 - total packet length    */
  uint16_t id;        /* +04 - identification         */
  uint16_t frag_off;  /* +06 - fragment offset field  */
  unsigned char ttl;        /* +08 - time to live           */
  unsigned char protocol;   /* +09 - ip protocol            */
  uint16_t check;     /* +10 - ip checksum            */
  uint32_t saddr;      /* +12 - source address         */
  uint32_t daddr;      /* +16 - destination address    */
};

struct ip_packet
{
    unsigned char hlv;
    unsigned char version;
    unsigned char header_length;
    uint16_t packet_length;
    uint16_t id;
    uint16_t fragment_offset;
    unsigned char ttl;
    unsigned char protocol;
    uint16_t checksum;
    uint32_t source;
    uint32_t destination;
    char source_a[16];
    char destination_a[16];
    void *start;
    void *end;
};

int process_ip_packet( struct ip_hdr *ip, struct ip_packet *packet );
int process_ip(unsigned char *buffer, int n, struct my_sockaddr_ll *from, struct packet_filter_rule *filters, int filter_idx);
#endif


#ifdef USE_ICMP
struct icmp_hdr
{
  unsigned char type;        /* 8 bits 0-7    - message type          */
  unsigned char code;        /* 8 bits 8-15   - type sub-code         */
  uint16_t checksum;   /* 16 bits 16-31 - icmp checksum         */
  uint16_t id;         /* 16 bits 32-47 - identification        */
  uint16_t sequence;   /* 16 bits 48-63 - sequence number       */
};

struct icmp_packet
{
  unsigned char type;
  unsigned char code;
  uint16_t checksum;
  uint16_t id;
  uint16_t seq;
  uint16_t length;
  void *start;
  void *end;
};

int process_icmp_packet( struct ip_packet *ip, struct icmp_hdr *icmp, struct icmp_packet *packet );
int tcpdump_print_icmp(struct ip_packet *packet_ip, struct icmp_packet *packet_icmp);
#endif


#ifdef USE_TCP
struct tcp_hdr
{
  uint16_t source;    /* 16 bits 0-15    - source port           */
  uint16_t dest;      /* 16 bits 16-31   - destination port      */
  uint32_t seq;        /* 32 bits 32-63   - sequence number       */
  uint32_t ack_seq;    /* 32 bits 64-95   - ack seq. number       */
  unsigned char unused;     /* 8 bits 96-103   - 4 bits data offset,   *
                                4 bits reserved                        */
  unsigned char flags;      /* 8 bits 104-111  - congestion window     *
                                reduced, ecn-echo, urgent, ack, psh,   *
                                rst, syn, fin                          */
  uint16_t window;    /* 16 bits 112-127 - tcp window size       */
  uint16_t check;     /* 16 bits 128-143 - tcp checksum          */
  uint16_t urp_ptr;   /* 16 bits 144-159 - urgent pointer        */
};

struct tcp_packet
{
  uint16_t source;
  uint16_t destination;
  struct flags {
      unsigned char urg;
      unsigned char ack;
      unsigned char psh;
      unsigned char rst;
      unsigned char syn;
      unsigned char fin;
  } flags;
  unsigned char header_length;
  uint16_t packet_length;
  uint32_t seq;
  uint32_t ack;
  uint16_t window;
  uint16_t checksum;
  uint16_t urgent;
  void *start;
  void *end;
};

int process_tcp_packet( struct ip_packet *ip, struct tcp_hdr *tcp, struct tcp_packet *packet );
#endif


#ifdef USE_UDP
struct udp_hdr
{
  uint16_t source;    /* 16 bits 0-15  - source port            */
  uint16_t dest;      /* 16 bits 16-31 - destination port       */
  uint16_t len;       /* 16 bits 32-47 - message length         */
  uint16_t check;     /* 16 bits 48-63 - udp checksum           */
};

struct udp_packet
{
  uint16_t source;
  uint16_t destination;
  uint16_t length;
  uint16_t checksum;
  uint16_t packet_length;
  void *start;
  void *end;
};

int process_udp_packet( struct ip_packet *ip, struct udp_hdr *udp, struct udp_packet *packet );
#endif


#ifdef USE_FILTERING
int filter_packet( struct my_sockaddr_ll *from, void *main_packet, void *packet, struct packet_filter_rule *filters, int filter_idx );
int parse_filter(int argc, char **argv, int i, struct packet_filter_rule *p);
#endif


static const struct protoent my_protocols[] = {
  { "icmp", NULL, 1 },
  { "igmp", NULL, 2 },
  { "tcp", NULL, 6 },
  { "udp", NULL, 17 },
  // ok fuck it; this is ethertypes not ip protocols so i can take a shortcut in the filtering function
  { "ip", NULL, ETH_P_IP },
  { "arp", NULL, ETH_P_ARP },
  { "ether", NULL, -1 },
  { NULL, NULL, 0 }
};

// for strspn, if we ever use it...
//const char *digits = "0123456789";
//const char *dotdigits = "0123456789.";

// miscellaneous crap useful in many functions
unsigned char debug;
FILE *F_logfd;
struct tm *lt;
struct timeval tv;


// stuff from etherdump.c
int show_usage(const char *extra);
uint32_t unsignedIntToLong(unsigned char *b);
unsigned char * nextword(unsigned char *string);
void * safe_malloc(size_t size);
struct protoent * my_getprotobynumber(int proto);
struct protoent * my_getprotobyname(unsigned char *name);
struct protoent * my_getproto(unsigned char *name);

