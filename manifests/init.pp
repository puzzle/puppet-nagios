# nagios.pp - everything nagios related
# Copyright (C) 2007 David Schmitt <david@schmitt.edv-bus.at>
# See LICENSE for the full license granted to you.
# adapted and improved by admin(at)immerda.ch
# adapted by Puzzle ITC - haerry+puppet(at)puzzle.ch


# the directory containing all nagios configs:
$nagios_cfgdir = "/var/lib/puppet/modules/nagios"
modules_dir{ nagios: }

class nagios {
    case $operatingsystem {
        debian: { include nagios::debian }
        centos: { include nagios::centos }
        default: { include nagios::base }
    }
}

class nagios::vars {
    case $operatingsystem {
        debian: {
            $etc_nagios_path =  "/etc/nagios2"
            }
        default: {
            $etc_nagios_path =  "/etc/nagios"
        }
    }
}

class nagios::base {

    # needs apache to work
    include apache

    package { nagios:
        ensure => present,   
    }

    service{nagios:
        ensure => running,
        enable => true,
        #hasstatus => true, #fixme!
        require => Package[nagios],
    }

    include nagios::vars
	
	# import the various definitions
	File <<| tag == 'nagios' |>>

    file {
		"$etc_nagios_path/htpasswd.users":
            source => [
                "puppet://$server/files/nagios/htpasswd.users",
                "puppet://$server/nagios/htpasswd.users"
            ],
            mode => 0640, owner => root, group => apache;
    }
    
    file {
        "$nagios_cfgdir/hosts.d":
            ensure => directory,
            owner => root,
            group => root,
            mode => 0755,
    }

	
	nagios::command {
		# from ssh.pp
		ssh_port:
			command_line => '/usr/lib/nagios/plugins/check_ssh -p $ARG1$ $HOSTADDRESS$';
		# from apache2.pp
		http_port:
			command_line => '/usr/lib/nagios/plugins/check_http -p $ARG1$ -H $HOSTADDRESS$ -I $HOSTADDRESS$';
		# from bind.pp
		nameserver: command_line => '/usr/lib/nagios/plugins/check_dns -H www.edv-bus.at -s $HOSTADDRESS$';
		# TODO: debug this, produces copious false positives:
		# check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$ --expected_address=$ARG3$ --warning=2.0 --critical=4.0';
		check_dig2: command_line => '/usr/lib/nagios/plugins/check_dig -H $HOSTADDRESS$ -l $ARG1$ --record_type=$ARG2$'
	}
    


    # additional hosts
    
    file {
        "$etc_nagios_path/hosts.cfg":
            source => [
                "puppet://$server/files/nagios/hosts.cfg",
                "puppet://$server/nagios/hosts.cfg",
                "puppet://$server/nagios/hostgroups_nagios2.cfg"
            ],
            mode => 0644, owner => nagios, group => nagios;
    }

    # nagios cfg includes $nagios_cfgdir/hosts.d
    file {
        "$etc_nagios_path/nagios.cfg":
			ensure => present, content => template( "nagios/nagioscfg.erb" ),
            mode => 0644, owner => nagios, group => nagios;
    }

	

    include munin::plugins::nagios
} # end nagios::base

class nagios::debian inherits nagios::base {
    Package [nagios]{
            name => "nagios2",
    }
    package {
        "nagios-plugins-standard":
            ensure => installed,
    }
	Service[nagios] {
			# Current Debian/etch pattern
			pattern => "/usr/sbin/nagios2 -d /etc/nagios2/nagios.cfg",
			subscribe => File [ $nagios_cfgdir ]
	}
    File["$etc_nagios_path/htpasswd.users"]{
        group => www-data,
    }

    file {
        [ "/etc/nagios2/conf.d/localhost_nagios2.cfg",
          "/etc/nagios2/conf.d/extinfo_nagios2.cfg",
          "/etc/nagios2/conf.d/services_nagios2.cfg" ]:
            ensure => absent,
            notify => Service[nagios];
    }
	# permit external commands from the CGI
    file {
       "/var/lib/nagios2":
            ensure => directory, mode => 751,
            owner => nagios, group => nagios,
            notify => Service[nagios];
    }
    file{
        "/var/lib/nagios2/rw":
            ensure => directory, mode => 2710,
            owner => nagios, group => www-data,
            notify => Service[nagios];

    }
	
	# TODO: these are not very robust!
	replace {
		# Debian installs a default check for the localhost. Since VServers
		# usually have no localhost IP, this fixes the definition to check the
		# real IP
		fix_default_config:
			file => "/etc/nagios2/conf.d/localhost_nagios2.cfg",
			pattern => "address *127.0.0.1",
			replacement => "address $ipaddress",
			notify => Service[nagios];
		# enable external commands from the CGI
		enable_extcommands:
			file => "/etc/nagios2/nagios.cfg",
			pattern => "check_external_commands=0",
			replacement => "check_external_commands=1",
			notify => Service[nagios];
		# put a cap on service checks
		cap_service_checks:
			file => "/etc/nagios2/nagios.cfg",
			pattern => "max_concurrent_checks=0",
			replacement => "max_concurrent_checks=30",
			notify => Service[nagios];
	}
    
}
# end nagios::debian

class nagios::centos inherits nagios::base {
    package { [ 'nagios-plugins-smtp','nagios-plugins-http', 'nagios-plugins-ssh', 'nagios-plugins-udp', 'nagios-plugins-tcp', 'nagios-plugins-dig', 'nagios-plugins-nrpe', 'nagios-plugins-load', 'nagios-plugins-dns', 'nagios-plugins-ping', 'nagios-plugins-procs', 'nagios-plugins-users', 'nagios-plugins-ldap', 'nagios-plugins-disk', 'nagios-devel', 'nagios-plugins-swap', 'nagios-plugins-nagios', 'nagios-plugins-perl' ]:
        ensure => 'present',
    }

    Service[nagios]{
        hasstatus => true,
    }
    
}

# include this class in every host that should be monitored by nagios
class nagios::target {
    nagios::host { $fqdn: }
	debug ( "$fqdn has $nagios_parent as parent" )
}

# defines
define nagios::host($ip = $fqdn, $short_alias = $fqdn) {
		@@file {
			"$nagios_cfgdir/hosts.d/${name}_host.cfg":
				ensure => present, content => template( "nagios/host.erb" ),
				mode => 644, owner => root, group => root,
				tag => 'nagios'
		}
	}

define nagios::service(
    $check_command = '', 
	$nagios_host_name = $fqdn, 
    $nagios_description = '' ){

	# this is required to pass nagios' internal checks:
	# every service needs to have a defined host
	include nagios::target
	$real_check_command = $check_command ? {
		'' => $name,
	    default => $check_command
	}
	$real_nagios_description = $nagios_description ? {
		'' => $name,
	    default => $nagios_description
	}
	@@file {"$nagios_cfgdir/hosts.d/${nagios_host_name}_${name}_service.cfg":
		ensure => present, content => template( "nagios/service.erb" ),
		mode => 644, owner => root, group => root,
	    tag => 'nagios'
    }
}

define nagios::extra_host($ip = $fqdn, $short_alias = $fqdn, $parent = "none") {
    $nagios_parent = $parent
	file {"$nagios_cfgdir/hosts.d/${name}_host.cfg":
		ensure => present, content => template( "nagios/host.erb" ),
		mode => 644, owner => root, group => root,
		notify => Service[nagios],
    }
}

define nagios::command($command_line) {
    file { "$nagios_cfgdir/hosts.d/${name}_command.cfg":
	    ensure => present, content => template( "nagios/command.erb" ),
		mode => 644, owner => root, group => root,
		notify => Service[nagios],
	}
}

