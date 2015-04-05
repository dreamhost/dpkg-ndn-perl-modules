#!/usr/bin/make -f
# -*- makefile -*-

SYS_PERL    := $(shell which perl)
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
DPAN_URI         := file://$(shell pwd)/dists/
DPAN_BUILD_DISTS := $(shell sed -e '/^\#/d' modules.list)
OURBUILD         := our-build
DPAN_CPANM_OPTS  := -q --self-contained -L scratch/ --save-dists=dists
BASE_CPANM_OPTS  := -q --from $(DPAN_URI) -L $(OURBUILD)
BUILD_CPANM_OPTS := $(BASE_CPANM_OPTS) --man-pages --notest
TEST_CPANM_OPTS  := $(BASE_CPANM_OPTS) --test-only

# our build target
INC_OURBUILD := -I $(OURBUILD)/lib/perl5 -I $(OURBUILD)/lib/perl5/$(ARCHNAME)

# testing options
HARNESS_OPTIONS  =
HARNESS_SUBCLASS = TAP::Harness::Restricted

# our cpanm invocation, full-length
CPANM = HARNESS_OPTIONS=$(HARNESS_OPTIONS) HARNESS_SUBCLASS=$(HARNESS_SUBCLASS) $(PERL) ./cpanm

META_DIR = $(OURBUILD)/lib/perl5/$(ARCHNAME)/.meta
installed_json = $(wildcard $(META_DIR)/*/install.json)
test_installed = $(addsuffix .test,$(installed_json))
show_installed = $(addsuffix .show,$(installed_json))

# shortcut function: get the pathname from a .meta/*/install.json
installed_json_to_pathname = `json_xs -e '$$_ = $$_->{pathname}' -t string < $(basename $@)`

override_dists := $(shell sed -e '/^\#/d' modules.list.overrides)

tmpfile := $(shell mktemp --tmpdir commit-msg.XXXXXXXX)

# this handles directory recursion, whereas install does not *le sigh*.  add a
# 'v' to have it tell you what it's doing.
INSTALL = cp -pRu

# targets to control our dist cache, etc

.PHONY: archname dpan index ndn-prefix commit-dists rebuild-dpan ndn-libdir \
	refresh-dists refresh-index help inject-override-dists \
	test-installed-packages $(test_installed) \
	show-installed-packages $(show_installed) \
	$(installed_json)

# dh will run the default target first, so make this the default!
all: build

bla: $(installed_json)
	for i in "$^" ; do json_xs -e '$$_ = $$_->{pathname}' -t string < $$i ; done

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

# see: https://github.com/tokuhirom/OrePAN2/issues/22
inject-override-dists:
	for i in $(override_dists) ; do orepan2-inject --no-generate-index --allow-dev $$i dists ; done
	orepan2-indexer --allow-dev $(DPAN_LOCATION)

gc:
	orepan2-gc dists

refresh-dpan: refresh-dists
	$(MAKE) refresh-index
	$(MAKE) commit-dists

refresh-dists: CPAN_BUILD_OPTS := $(DPAN_BUILD_OPTS)
#refresh-dists: PERL            := $(SYS_PERL)
refrest-dists: build

# note we deliberately do *not* set a CPAN mirror here.  This is intentional.
refresh-dists-xxx:
	# download dists
	$(PERL) ./cpanm -q --exclude-vendor \
		--self-contained -L scratch/ --save-dists=dists \
		--notest \
		$(DPAN_BUILD_DISTS)

dpan: index

index: dists
	$(MAKE) refresh-index

refresh-index:
	orepan2-indexer --allow-dev $(DPAN_LOCATION)
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
	rm -rf our-build/ build.sh build-stamp

build: build-stamp

build-stamp: build.sh
	time ./build.sh
	touch build-stamp

refresh.sh: build.sh.tmpl modules.list
	cp build.sh.tmpl $@ 
	echo "$(PERL) ./cpanm $(BUILD_CPANM_OPTS) TAP::Harness::Restricted" >> $@
	cat modules.list \
		| sed -e '/^#/d' \
		| xargs -L1 echo "HARNESS_SUBCLASS=TAP::Harness::Restricted $(PERL) ./cpanm $(BUILD_CPANM_OPTS)" \
		>> $@

module_deps := $(shell sed -e "/^\#/d" modules.list)
module_targets := $(subst ::,-,$(module_deps))
.PHONY: $(module_targets) build-ng
build-ng: $(module_targets)

$(module_targets):
	HARNESS_SUBCLASS=TAP::Harness::Restricted $(PERL) ./cpanm $(BUILD_CPANM_OPTS) $(subst -,::,$@)

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
	$(INSTALL) $(OURBUILD)/lib/perl5/* $(DESTDIR)/$(NDN_LIB)/
	# scripties, binaries, whatnot...
	mkdir -p $(DESTDIR)/$(NDN_BIN)
	$(INSTALL) $(OURBUILD)/bin/* $(DESTDIR)/$(NDN_BIN)/
	# man pages...
	mkdir -p $(DESTDIR)/$(NDN_MAN)
	$(INSTALL) $(OURBUILD)/man/* $(DESTDIR)/$(NDN_MAN)/
	# ...and clean it all up.
	find $(DESTDIR) -empty -name '*.bs' -exec rm -vf {} \;
	find $(DESTDIR) -name '.packlist' -exec rm -vf {} \;
	find $(DESTDIR) -name 'perllocal.pod' -exec rm -vf {} \;
	find $(DESTDIR) -empty -type d -delete
	chmod -Rf a+rX,u+w,g-w,o-w $(DESTDIR)

$(installed_json):

$(show_installed): $(installed_json)
	@echo `json_xs -e '$$_ = $$_->{pathname}' -t string < $(basename $@)`

show-installed: $(show_installed)

$(test_installed): $(installed_json)
	$(CPANM) $(TEST_CPANM_OPTS) $(installed_json_to_pathname) 

test-installed-packages: $(test_installed)

test: test-installed-packages

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
	#   gc:                    remove tarballs not indexed
	#   rebuild-dpan:          remove our dpan (./dists/) and completely
	#       rebuild.  This will take some time.
	#   refresh-dists:         refresh the dpan with modules.list
	#       changes w/o obliterating the dpan first
	#   inject-override-dists: inject the override dists, typically from a git
	#       repository somewhere, as listed in modules.list.overrides
	#   dev-clean:             removes "admin artifacts"; depends on "clean"
	#   show-outdated:         show the dists in our DPAN that have newer
	#       releases on the public CPAN
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
