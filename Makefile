
# change this to "our" perl; but for now...
#PERL = $(/opt/ndn-perl/bin/perl)
PERL        := PERL5LIB="" PERL_CPANM_OPT="" /opt/ndn-perl/bin/perl
PERL_PREFIX := $(shell $(PERL) -MConfig -E 'say $$Config{prefix}')
SITELIB     := $(shell $(PERL) -MConfig -E 'say $$Config{sitelib}')
SITEARCH    := $(shell $(PERL) -MConfig -E 'say $$Config{sitearch}')
ARCHNAME    := $(shell $(PERL) -MConfig -E 'say $$Config{archname}')
BINDIR      := $(shell $(PERL) -MConfig -E 'say $$Config{bindir}')

NDN_LIB := $(PERL_PREFIX)/modules/perl5
NDN_BIN := $(BINDIR)
NDN_MAN := $(PERL_PREFIX)/modules/man

# this should be changed to 'Task::NDN' or the like
PRIMARY_DIST := $(shell cat modules.list) 
#DPAN_BUILD_DISTS := $(PRIMARY_DIST) Module::Build
DPAN_LOCATION    := ./dists/
DPAN_BUILD_DISTS := $(shell cat modules.list)
# if we want to be using a DPAN external to this repo, too
CPAN_MIRROR  := 'https://stratopan.com/rsrchboy/Test/master'
HARNESS_OPTIONS :=
# we may want to set this to TAP::Harness::Restricted
HARNESS_SUBCLASS :=
OURBUILD         := our-build
BUILD_CPANM_OPTS := -q --from file://`pwd`/dists/ \
	-L $(OURBUILD) --man-pages

# our build target
INC_OURBUILD := -I $(OURBUILD)/lib/perl5 -I $(OURBUILD)/lib/perl5/$(ARCHNAME)

tmpfile := $(shell tempfile)

# targets to control our dist cache, etc

.PHONY: archname dpan index ndn-prefix commit-dists rebuild-dpan ndn-libdir \
	refresh-dists refresh-index help

# dh will run the default target first, so make this the default!
all: build

archname:
	@echo $(ARCHNAME)

ndn-prefix:
	@echo $(PERL_PREFIX)

ndn-libdir:
	@echo $(NDN_LIB)

dev-clean: clean
	rm -rf dists/ scratch/

commit-dists:
	# commiting changes to dists/
	git add -A dists/
	echo 'CPAN Updates' >> $(tmpfile)
	echo                >> $(tmpfile)
	git status --porcelain \
		| perl -nE 'chomp; say unless /^[ M\?]/' \
		| grep -v  '02packages' \
		| perl -pE 's!dists/authors/id/./../!!m' \
		| sed -e 's/\// /' \
		| sed -e 's/\// /' \
		| sed -e 's/^A/ADDED/; s/^D/DELETED/; s/^M/MODIFIED/' \
		| sort -dk3 \
		| column -t \
		| tee -a $(tmpfile)
	git commit --file=$(tmpfile)

dists: refresh-dists

refresh-dpan: refresh-dists
	$(MAKE) refresh-index
	$(MAKE) commit-dists

# note we deliberately do *not* set a CPAN mirror here.  This is intentional.
refresh-dists:
	# download dists
	$(PERL) ./cpanm -q --exclude-vendor \
		--self-contained -L scratch/ --save-dists=dists \
		$(DPAN_BUILD_DISTS)

dpan: index

index: dists
	$(MAKE) refresh-index

refresh-index:
	orepan2-indexer $(DPAN_LOCATION)
	orepan2-gc $(DPAN_LOCATION)

show-outdated:
	orepan2-audit \
		--darkpan $(DPAN_LOCATION)/modules/02packages.details.txt.gz \
		--cpan http://cpan.metacpan.org/modules/02packages.details.txt \
		--show outdated-modules

rebuild-dpan: dev-clean
	$(MAKE) dpan
	$(MAKE) commit-dists

# targets that will get invoked by dh: clean, build, test

clean:
	rm -rf our-build/ build.sh

build: build.sh
	time ./build.sh

build.sh: build.sh.tmpl modules.list
	cp build.sh.tmpl build.sh
	echo "$(PERL) ./cpanm $(BUILD_CPANM_OPTS) TAP::Harness::Restricted" >> build.sh
	cat modules.list \
		| sed -e '/^#/d' \
		| xargs -L1 echo "HARNESS_SUBCLASS=TAP::Harness::Restricted $(PERL) ./cpanm $(BUILD_CPANM_OPTS)" \
		>> build.sh

install:
	# perl libs...
	mkdir -p $(DESTDIR)/$(NDN_LIB)
	mv $(OURBUILD)/lib/perl5/* $(DESTDIR)/$(NDN_LIB)/
	# scripties, binaries, whatnot...
	mkdir -p $(DESTDIR)/$(NDN_BIN)
	mv $(OURBUILD)/bin/* $(DESTDIR)/$(NDN_BIN)/
	# man pages...
	mkdir -p $(DESTDIR)/$(NDN_MAN)
	mv $(OURBUILD)/man/* $(DESTDIR)/$(NDN_MAN)/
	# ...and clean it all up.
	find $(DESTDIR) -empty -name '*.bs' -exec rm -vf {} \;
	find $(DESTDIR) -name '.packlist' -exec rm -vf {} \;
	find $(DESTDIR) -name 'perllocal.pod' -exec rm -vf {} \;
	find $(DESTDIR) -empty -type d -delete
	chmod -Rf a+rX,u+w,g-w,o-w $(DESTDIR)

test:
	# no-op, already done in build

help:
	# Hi!  This is the make program, telling you about this delicious Makefile
	# I'm reading.  We have a number of targets you can enjoy today, loosely
	# grouped into "admin" and "normal" targets.
	#
	# "admin" targets are intended to be used by package/DPAN maintainers, on
	# their own machines.  They require a sane perl (system perl or otherwise)
	# be available, as well as the OrePAN2 tools.  An ideal machine to run
	# this on would be, say, your laptop, rather than a shared fubar-ed
	# machine.  "admin" targets are not run by the build process (debuild,
	# "normal" targets, and the like).
	#
	# "normal" targets are, well, what one expects: build, install, test, etc.
	# They may called by debuild, and should not depend on anything not listed
	# as a build-depends in debian/control.  (Or your life will be
	# interesting.)  These are the targets that will build and install from
	# the lists and DPAN built and maintained by the "admin" targets.  They
	# also include targets like this one, "help".
	#
	# The default target (aka "what gets run when make is invoked w/o an
	# explicit target") is build.
	#
	# Targets invoked by debuild/dpkg-buildpackage/debhelper: clean, build,
	# test, and install.
	#
	# admin/dev targets:
	#   rebuild-dpan:  remove our dpan (./dists/) and completely rebuild
	#   refresh-dists: refresh the dpan with modules.list changes w/o
	#                  obliterating the dpan first
	#   dev-clean:     removes "admin artifacts"; depends on "clean"
	#   show-outdated: show the dists in our DPAN that have newer releases on
	#                  the public CPAN
	#
	# normal targets:
	#   help:    display this help
	#   build:   build out our modules
	#   install: install our built modules to DESTDIR (depends on build)
	#   test:    currently a no-op; testing is handled on a per-dist basis by
	#            cpanm during the "build" stage
	#   clean:   wipe all build artifacts
	#
	# lesser-used normal targets:
	#   build.sh: generate the script used to build our modules
