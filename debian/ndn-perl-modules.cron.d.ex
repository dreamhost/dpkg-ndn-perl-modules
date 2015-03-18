#
# Regular cron jobs for the ndn-perl-modules package
#
0 4	* * *	root	[ -x /usr/bin/ndn-perl-modules_maintenance ] && /usr/bin/ndn-perl-modules_maintenance
