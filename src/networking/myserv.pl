#!/usr/bin/perl
$|=1;

use IO::Socket::INET;
use IPC::Open2;

$rsync = "/spln/pwillis/home/Desktop/Source/rsync-3.0.5/rsync --daemon";

$s=IO::Socket::INET->new(Listen=>"1",LocalAddr=>"localhost:2996",Proto=>tcp,Timeout=>10,Blocking=>0,ReuseAddr=>1);

sub handle_close { close $s; close $c; exit(0); };

$SIG{INT} = \&handle_close;
$SIG{TERM} = \&handle_close;

my ($pipe_out, $pipe_in);

while($c=$s->accept()){
    $pid = open2($pipe_out, $pipe_in, "$rsync") || die "Cannot open pipe: $!";
    for(;;){
        print STDERR "reading from network socket\n";
        recv($c,$buf,8192,MSG_TRUNC);
        if (length($buf)>0){
            #print "buf len " . length($buf) . "\n";
            #print "buf: \"$buf\"\n";
            print STDERR "writing \"$buf\" to pipe\n";
            syswrite($pipe_out, $buf);
        }
        $buf="";

        print STDERR "reading from pipe\n";
        sysread($pipe_in, $buf, 8192);
        if (length($buf)>0) {
            print STDERR "writing \"$buf\" to network socket\n";
            syswrite($c, $buf);
        }
    }
}

