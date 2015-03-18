
# change this to "our" perl; but for now...
#PERL = $(/opt/ndn-perl/bin/perl)
PERL  = /usr/bin/perl

# this should be changed to 'Task::NDN' or the like
PRIMARY_DIST = Moose
CPAN_MIRROR  = 'https://stratopan.com/rsrchboy/Test/master'
#CPANM_OPTS   = "--mirror-only --mirror $(CPAN_MIRROR)"

# targets to control our dist cache, etc

dists: dists.list

dists.list:
	# download dists
	$(PERL) ./cpanm --self-contained -q \
		-L scratch/ \
		--scandeps --format=dists --save-dists=dists \
		$(CPANM_OPTS) $(PRIMARY_DIST) > dists.list

# targets that will get invoked by dh: clean, build, test

clean:
	rm -rf dists/ scratch/ dists.list

#build:

#test:


