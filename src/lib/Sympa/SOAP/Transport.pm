# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id$
#
# Sympa - SYsteme de Multi-Postage Automatique
#
# Copyright (c) 1997, 1998, 1999 Institut Pasteur & Christophe Wolfhugel
# Copyright (c) 1997, 1998, 1999, 2000, 2001, 2002, 2003, 2004, 2005,
# 2006, 2007, 2008, 2009, 2010, 2011 Comite Reseau des Universites
# Copyright (c) 2011, 2012, 2013, 2014, 2015, 2016, 2017 GIP RENATER
# Copyright 2017 The Sympa Community. See the AUTHORS.md file at the top-level
# directory of this distribution and at
# <https://github.com/sympa-community/sympa.git>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

package Sympa::SOAP::Transport;

use strict;
use warnings;
use SOAP::Transport::HTTP;

use Sympa::Log;
use Sympa::Session;
use Sympa::Tools::WWW;

# 'base' pragma doesn't work here
our @ISA = qw(SOAP::Transport::HTTP::FCGI);

my $log = Sympa::Log->instance;

sub request {
    my $self = shift;

    if (my $request = $_[0]) {
        # Select appropriate robot.
        $ENV{'SYMPA_ROBOT'} =
            Sympa::Tools::WWW::get_robot('soap_url_local', 'soap_url');

        ## Empty cache of the List.pm module
        Sympa::List::init_list_cache();

        my $session;
        ## Existing session or new one
        if (Sympa::Session::get_session_cookie($ENV{'HTTP_COOKIE'})) {
            $session = Sympa::Session->new(
                $ENV{'SYMPA_ROBOT'},
                {   'cookie' => Sympa::Session::get_session_cookie(
                        $ENV{'HTTP_COOKIE'}
                    )
                }
            );
        } else {
            $session = Sympa::Session->new($ENV{'SYMPA_ROBOT'}, {});
            $session->store() if (defined $session);
            ## Note that id_session changes each time it is saved in the DB
            $session->renew()
                if (defined $session);
        }

        delete $ENV{'USER_EMAIL'};
        if (defined $session) {
            $ENV{'SESSION_ID'} = $session->{'id_session'};
            if ($session->{'email'} ne 'nobody') {
                $ENV{'USER_EMAIL'} = $session->{'email'};
            }
        }
    }

    $self->SUPER::request(@_);
}

sub response {
    my $self = shift;

    if (my $response = $_[0]) {
        if (defined $ENV{'SESSION_ID'}) {
            my $expire = $main::param->{'user'}{'cookie_delay'}
                || $Conf::Conf{'cookie_expire'};
            my $cookie =
                Sympa::Session::soap_cookie2($ENV{'SESSION_ID'},
                $ENV{'SERVER_NAME'}, $expire);
            $response->headers->push_header('Set-Cookie2' => $cookie);
        }
    }

    $self->SUPER::request(@_);
}

## Redefine FCGI's handle subroutine
sub handle ($$$) {
    my $self     = shift->new;
    my $birthday = shift;
    my $myname   = shift;

    my ($r1, $r2);
    my $fcgirq = $self->{_fcgirq};

    while (($r1 = $fcgirq->Accept()) >= 0) {

        $r2 = $self->SOAP::Transport::HTTP::CGI::handle;

        # Exit if script itself has changed.
        if (defined $birthday and $myname) {
            my $age = [stat $myname]->[9];
            if (defined $age and $birthday != $age) {
                $log->syslog(
                    'notice',
                    'Exiting because %s has changed since FastCGI server started',
                    $myname
                );
                exit(0);
            }
        }
    }
    return undef;
}

1;
