#!/usr/bin/perl

use strict;
use threads;
use Telegram::Bot;
use HTTP::Daemon;
use POSIX qw(strftime);
use Encode qw(encode);
use Data::Dumper;
use JSON;
use LWP::Simple;
use IO::Socket::UNIX;

use forks;
use forks::shared deadlock => {detect=> 1, resolve => 1};

use lib '.';
use Fenite qw(query update insert);

my @send_messages;
my @all;

my @mmgs = ();
my $op = "";
my @o = ();
my @mm = ();
my @r = ();
my $regex = "";
my %resp = ();

share(@mmgs);
share($regex);
share(%resp);

# Bot
my $bot = new Telegram::Bot;

my $codename = $bot->{config}{codename};
my $ownchat = $bot->{config}{ownchat};

$SIG{CHLD} = 'IGNORE';

local $SIG{__WARN__} = sub {
    my $message = shift;
    print $message . "\n";
};

if(!$bot->{config}{log}{state}) {
    open(STDOUT, ">/dev/null");
    open(STDERR, ">/dev/null");
}

sub _reload {
    my $SOCK_PATH = "$ENV{HOME}/fenite.sock";
    
    if(-e $SOCK_PATH) { 
	    unlink($SOCK_PATH);
    }

    my $server = IO::Socket::UNIX->new(
        Type => SOCK_STREAM(),
        Local => $SOCK_PATH,
        Listen => 1,
    );

    while(1) {
        next unless my $conn = $server->accept();
	    $conn->autoflush(1);
	    while(<$conn>) {
	       _load();
	    }
    }
}

sub _load {
    # MMGs 
    undef @mmgs;
    @mmgs = ();
    @mmgs = query("select frase, type from fenite_frases order by random()");

    # Operadores
    undef @o;
    @o = ();
    @o = query("select codename from fenite_op");
    $op = join("|", @o);
    $op =~ s/\s\n|\n//g;

    # Regex
    undef $regex;
    @r = ();
    @r = query("select regex from fenite_regex");
    $regex = join("|", @r);
    $regex =~ s/\s\n|\n//g;

    # Resp
    my @re = ();
    @re = query("select key, frase, type from fenite_rep");
    undef %resp;
    %resp = ();

    foreach my $tmp (@re) {
        my @t = split(/\|/, $tmp);
        $resp{$t[0]} = "$t[1]|$t[2]";
    }
}

_load();

# Reload thread
threads->create(\&_reload)->detach();

while(1) {
    my $msg = $bot->start();
    _process($msg);
}

sub _process {
    my $msg = shift;

    my $username = $msg->{from}{username};
    my $firstname = $msg->{from}{first_name};
    my $id = $msg->{from}{id};
    my $tme = "[" . encode("utf8", $firstname) . "](tg://user?id=" . $id. ")";

    if($msg->{new_chat_member}) {
        if($msg->{new_chat_member}{username} eq $codename) {
            my $text = $tme . " me entro en el grupo *" . $msg->{chat}{title} . "*";
            _msg($ownchat, $text);

            $text = "Hola grupo, el mmg de " . $tme . " me invito!!";
            _msg($msg->{chat}{id}, $text);
        }else{
            my $nme = "[" . encode("utf8", $msg->{new_chat_member}{firstname}) . "](tg://user?id=" . $msg->{new_chat_member}{id} . ")";
            my $text = $nme . " klk";

            _msg($msg->{chat}{id}, $text);
        }
        return;
    }

    if($msg->{left_chat_member}) {
        if($msg->{left_chat_member}{username} eq $codename) {
            my $text = $tme . " me saco del grupo *" . $msg->{chat}{title} . "*";
            _msg($ownchat, $text);
        }else{
            my $text = "Que le vaya bien a ese mmg";
            _msg($msg->{chat}{id}, $text);
        }
        return;
    }

    my $username_reply;
    my $firstname_reply;
    my $id_reply;
    my $tme_reply;

    if($msg->{reply_to_message}) {
        $username_reply = $msg->{reply_to_message}{from}{username};
        $firstname_reply = $msg->{reply_to_message}{from}{first_name};
        $id_reply = $msg->{reply_to_message}{from}{id};
        $tme_reply = "[" . encode("utf8", $firstname_reply) . "](tg://user?id=" . $id_reply. ")";
    }
    
    my $text = $msg->{text};
    $text .= $msg->{caption};
    $text .= $msg->{reply_to_message}{text} if $text !~ /^\//;
    $text .= $msg->{reply_to_message}{caption} if $text !~ /^\//;

    # Responder a los MMGS
    if($text =~ /$regex/i) {
        my $m = $mmgs[rand @mmgs];
        chomp($m);

        _send($msg, $m, $tme);

        $username =~ s/\@|\s//g;
        mmg($msg->{chat}{id}, $username, $id, $firstname, $msg->{chat}{title});
        return;
    }

    # Responder a di lo tuyo
    if($text =~ /di lo tuyo|Say your thing/i) {
        my $m = $mmgs[rand @mmgs];
        chomp($m);
        
        if((!$firstname_reply && !$username_reply) || $username_reply eq $codename) {
            _send($msg, $m, $tme);
        }else{
            _send($msg, $m, $tme_reply);
        }

        return;
    }

    # Commandos en plugins
    if($msg->{text} =~ /^\//) {
        threads->create(sub{$bot->process($msg);})->detach();
        return;
    }else{
        # Responder texto
        foreach my $key (keys %resp) {
            if($msg->{text} =~ /$key[\s\n\r?!\.]|$key$/i) {
                _send($msg, $resp{$key});
                last;
            }
        }
    }

}

sub _msg {
    my $id = shift;
    my $text = shift;

    $bot->sendMessage([
        chat_id => $id,
        text => $text,
        parse_mode => 'Markdown',
        disable_web_page_preview => 'true'
    ]);
}

sub _send {
    my $msg = shift;
    my $m = shift;
    my $codename = shift;

    my @t = split(/\|/, $m);
    if($t[1] eq "document") {
        $bot->sendDocument([
            chat_id => $msg->{chat}{id},
            document => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "photo") {
        $bot->sendPhoto([
            chat_id => $msg->{chat}{id},
            photo => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "voice") {
        $bot->sendVoice([
            chat_id => $msg->{chat}{id},
            voice => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "audio") {
        $bot->sendAudio([
            chat_id => $msg->{chat}{id},
            audio => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "video") {
        $bot->sendVideo([
            chat_id => $msg->{chat}{id},
            video => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "animation") {
        $bot->sendVideo([
            chat_id => $msg->{chat}{id},
            animation => $t[0],
            caption => $codename,
            parse_mode => 'Markdown'
        ]);
    }elsif($t[1] eq "sticker") {
        if($codename) {
            $bot->sendMessage([
                chat_id => $msg->{chat}{id},
                text => $codename,
                parse_mode => 'Markdown'
            ]);
        }
        $bot->sendSticker([
            chat_id => $msg->{chat}{id},
            sticker => $t[0]
        ]);
    }else{
        $m = $codename . " " . $t[0];
        $bot->sendMessage([
            chat_id => $msg->{chat}{id},
            text => $m,
            parse_mode => 'Markdown',
            disable_web_page_preview => 'true'
        ]);
    }
}

sub mmg {
    my $chatid = shift;
    my $codename = shift;
    my $id = shift;
    my $firstname = shift;
    my $chat = shift;

    $codename = "*NA*" if(!$codename);
    $chat = "private" if(!$chat);

    my $year = strftime "%Y", localtime;

    # Select
    my $query = "select count(*) from fenite_mmg where id = ? and chatid = ? and year = ?";
    my @param = ($id, $chatid, $year);
    my @ret = query($query, @param);

    my $qry = "";
    my @param_qry = ();

    if($ret[0] > 0) {
        # UPDATE CON ID
        $qry = "update fenite_mmg set count = count + 1, codename = ?, firstname = ?, chat = ? where id = ? and chatid = ? and year = ?";
        @param_qry = ($codename, $firstname, $chat, $id, $chatid, $year);
    }else{
        @param = ();
        @ret = ();

        $query = "select count(*) from fenite_mmg where codename = ? and chatid = ? and year = ?";
        @param = ($codename, $chatid, $year);
        @ret = query($query, @param);

        if($ret[0] > 0) {
            # Update
            $qry = "update fenite_mmg set count = count + 1, id = ?, firstname = ?, chat = ? where codename = ? and chatid = ? and year = ?";
            @param_qry = ($id, $firstname, $chat, $codename, $chatid, $year);
        }else{
            # Insert
            $qry = "insert into fenite_mmg (codename, chatid, count, year, id, firstname, chat) values (?,?,1,?,?,?,?)";
            @param_qry = ($codename, $chatid, $year, $id, $firstname, $chat);
        }
    }

    insert($qry, @param_qry);
}

