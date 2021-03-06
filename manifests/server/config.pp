# Class: gitolite::server::config
#
# Description
#  This class is designed to configure the system to use Gitolite and Gitweb
#
# Parameters:
#  $site_name: (default: "fqdn Git Repository") The friendly name displayed on
#              the GitWeb main page.
#  $manage_apache: flag to determine whether gitolite module also manages Apache
#                  configuration
#  $server_admin: the admin email for Apache::Vhost
#  $write_apache_conf_to: (file path). This option is used when you want to
#                         contain apache configuration within the gitolite
#                         class, but do not want to use the puppetlabs-apache
#                         module to manage apache. This option takes a file
#                         path and will write the apache template to a specific
#                         file on the filesystem.
#                         REQUIRES: $apache_notify
#  $apache_notify: Reference notification to be used if the gitolite module will
#                  manage apache, but the puppetlabs-apache module is not
#                  going to be used. This takes a type reference (e.g.:
#                  Class['apache::service'] or Service['apache2']) to send
#                  a notification to the reference to restart an external
#                  apache service.
#  $vhost: the virtual host of the apache instance.
#  $ssh_key: the SSH key used to seed the admin account for gitolite.
#  $safe_config: Hash of variable name => value to add to SAFE_CONFIG.
#  $grouplist_pgm: An external program called to determine user groups
#                  (see http://gitolite.com/gitolite/auth.html#ldap)
#  $enable_features: Enable these FEATURES in gitolite configuration, in
#                    addition to the hard-coded ones.
#  $git_config_keys: Regular expression to configure GIT_CONFIG_KEYS.
#  $local_code: path to a directory to add or override gitolite programs
#               (see http://gitolite.com/gitolite/cust.html#localcode)
#  $gitweb_projectslist_ensure: one of file or link
#                              'file' will require additional content arg
#                              'link' will require additional target path arg
#  $gitweb_projectslist_content: string content
#  $gitweb_projectslist_target_path: full target file path
#
# Actions:
#  Configures gitolite/gitweb
#
# Requires:
#  This module has no requirements
#
# Sample Usage:
#  This module should not be called directly.
class gitolite::server::config (
  $site_name,
  $manage_apache,
  $server_admin,
  $write_apache_conf_to,
  $apache_notify,
  $vhost,
  $ssh_key,
  $safe_config,
  $grouplist_pgm,
  $enable_features,
  $git_config_keys,
  $local_code,
  $gitweb_projectslist_ensure      = $gitolite::gitweb_projectslist_ensure,
  $gitweb_projectslist_content     = $gitolite::gitweb_projectslist_content,
  $gitweb_projectslist_target_path = $gitolite::gitweb_projectslist_target_path,
) {
  File {
    owner => $gitolite::params::gt_uid,
    group => $gitolite::params::gt_gid,
    mode  => '0644',
  }
  Exec {
    path => '/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bin:/usr/local/sbin',
  }

  # gitolite User Setup
  user { $gitolite::params::gt_uid:
    ensure  => present,
    home    => $gitolite::params::gt_repo_base,
    gid     => $gitolite::params::gt_gid,
    comment => 'git repository hosting',
  }
  group { $gitolite::params::gt_gid:
    ensure  => present,
  }
  # Git Filesystem Repository Setup
  file { $gitolite::params::gt_repo_base:
    ensure => directory,
  }
  file { "${gitolite::params::gt_httpd_conf_dir}/git.conf":
    ensure => absent,
  }

  # Gitweb Setup
  # Template uses:
  # - gitolite::params::gt_repo_dir
  # - gitolite::params::gt_gitweb_spath
  # - vhost
  # - site_name
  file { '/etc/gitweb.conf':
    ensure  => file,
    content => template('gitolite/gitweb.conf.erb'),
  }
  ## add pretty style sheets
  file { "${gitolite::params::gt_gitweb_root}${gitolite::params::gt_gitweb_spath}":
    ensure => directory,
  }
  $gitweb_static_files = ['gitweb.css', 'gitweb.js', 'git-favicon.png', 'git-logo.png' ]
  each($gitweb_static_files) |$f| {
    file {
      "${gitolite::params::gt_gitweb_root}${gitolite::params::gt_gitweb_spath}${f}":
        ensure  => file,
        source  => "puppet:///modules/gitolite/${f}",
        require =>
        File["${gitolite::params::gt_gitweb_root}${gitolite::params::gt_gitweb_spath}"],
    }
  }

  # Flag modifier to allow user to choose whether to use
  # puppetlabs-apache module to manage apache config
  # -JDF (12/1/2011)
  if $manage_apache == true {
    # This flag allows other non- puppetlabs-apache modules to still be managed
    # by this module
    # Based on code provided by justone. Ref:
    # https://github.com/jfryman/puppet-gitolite/pull/2
    # -JDF (12/1/2011)

    # Template uses:
    # - gitolite::params::gt_gitweb_root
    # - gitolite::params::gt_gitweb_binary
    # - gitolite::params::gt_repo_dir
    # - gitolite::params::gt_httpd_conf_dir
    # - vhost
    if $write_apache_conf_to != '' {
      if $apache_notify == '' {
        fail('Cannot properly manage Apache if a refresh reference is not specified')
      } else {
        file { $write_apache_conf_to:
          ensure  => file,
          content => template('gitolite/gitweb-apache-vhost.conf.erb'),
          notify  => $apache_notify,
          require => [
            File['/etc/gitweb.conf'],
            File["${gitolite::params::gt_httpd_conf_dir}/git.conf"]
          ],
        }
      }
    }
    else {
      # By default, use the puppetlabs-apache module to manage Apache
      apache::vhost { $vhost:
        serveradmin    => $server_admin,
        port           => '80',
        docroot        => $gitolite::params::gt_gitweb_root,
        manage_docroot => false,
        setenv         => [
          'GITWEB_CONFIG   /etc/gitweb.conf',
        ],
        directories => [
          {
            path           => $gitolite::params::gt_gitweb_root,
            directoryindex => $gitolite::params::gt_gitweb_binary,
            options        => ['FollowSymLinks','ExecCGI'],
            allow_override => 'All',
            addhandlers    => [
              { handler    => 'cgi-script', extensions => ['.cgi']}
            ],
            rewrites       => [
              {
                rewrite_cond   => [
                  '%{REQUEST_FILENAME} !-f',
                  '%{REQUEST_FILENAME} !-d',
                ],
                rewrite_rule   => [
                  "^.* /${gitolite::params::gt_gitweb_binary}/\$0 [L,PT]",
                ],
              },
            ],
          },
          {
            path           => $gitolite::params::gt_repo_dir,
            allow_override => 'All',
          },
        ],
        log_level         => debug,
        error_log_file    => "${vhost}_error.log",
        access_log_file   => "${gitolite::params::gt_httpd_var_dir}/${vhost}_access.log",
        access_log_format => combined,
        ssl               => false,
        priority          => '99',
        notify            => Service[apache2],
        require           => [
          File['/etc/gitweb.conf'],
          File["${gitolite::params::gt_httpd_conf_dir}/git.conf"]
        ],
      }
    }
  }

  # Gitolite Configuration
  file { "${gitolite::params::gt_repo_base}/.bash_history":
    ensure => 'absent',
  }
  file { 'gitolite-key':
    ensure  => file,
    path    => "${gitolite::params::gt_repo_base}/gitolite.pub",
    content => $ssh_key,
  }
  exec { 'install-gitolite':
    command     => "gitolite setup -pk ${gitolite::params::gt_repo_base}/gitolite.pub",
    creates     => "${gitolite::params::gt_repo_base}/projects.list",
    cwd         => $gitolite::params::gt_repo_base,
    user        => $gitolite::params::gt_uid,
    environment => "HOME=${gitolite::params::gt_repo_base}",
    require     => File['gitolite-key'],
  }

  $final_projectlist_content = case $gitweb_projectslist_ensure {
    'file': { $gitweb_projectslist_content }
    'link': { undef }
  }
  file { "${gitolite::params::gt_repo_base}/projects.list":
    ensure  => $gitweb_projectslist_ensure,
    content => $final_projectlist_content,
    target  => $gitweb_projectslist_target_path,
    mode    => '0644',
    require => Exec['install-gitolite'],
  }

  # Template uses $enable_features
  file { 'gitolite-config':
    path    => "${gitolite::params::gt_repo_base}/.gitolite.rc",
    content => template('gitolite/gitolite.rc.erb'),
    require => Exec['install-gitolite'],
  }
}
