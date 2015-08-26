#!/usr/bin/make -f
# -*- makefile -*-

# TODO:
#
# [x] DPAN build/rebuild/refresh targets.
#   [x] Move utility targets
# [x] Build targets swizzle
#   [x] stash-built-tree-to-test
# [ ] Test targets swizzle
# [ ] clean targets
# [ ] group utility targets



# how we invoke our ndn-perl; note how things can be tweaked by overriding
# various variable settings.
NDN_PERL = /opt/ndn-perl/bin/perl

SYS_PERL    := $(shell which perl)
PERL_PREFIX := $(shell $(NDN_PERL) -MConfig -E 'say $$Config{prefix}')
SITELIB     := $(shell $(NDN_PERL) -MConfig -E 'say $$Config{sitelib}')
SITEARCH    := $(shell $(NDN_PERL) -MConfig -E 'say $$Config{sitearch}')
ARCHNAME    := $(shell $(NDN_PERL) -MConfig -E 'say $$Config{archname}')
BINDIR      := $(shell $(NDN_PERL) -MConfig -E 'say $$Config{scriptdir}')

NDN_LIB = $(PERL_PREFIX)/modules/perl5
NDN_BIN = $(BINDIR)
NDN_MAN = $(PERL_PREFIX)/modules/man

TO_INSTALL := $(shell sed -e '/^\#/d' modules.list)

DPAN_LOCATION     = ./dists/
DPAN_URI          = file://$(shell pwd)/dists/
DPAN_BUILD_DISTS := $(shell sed -e '/^\#/d' modules.list)
OURBUILD          = our-build
DPAN_CPANM_OPTS   = -q -L scratch/ --notest --save-dists=dists
BASE_CPANM_OPTS   = -q --from $(DPAN_URI) -L $(OURBUILD)
BUILD_CPANM_OPTS  = $(BASE_CPANM_OPTS) --man-pages --notest
TEST_CPANM_OPTS   = $(BASE_CPANM_OPTS) --test-only

# our build target
INC_OURBUILD = -I $(OURBUILD)/lib/perl5/$(ARCHNAME) -I $(OURBUILD)/lib/perl5

# testing options (mostly)
env_automated_testing = 1
env_harness_options   =
env_harness_subclass  = TAP::Harness::Restricted
env_perl5lib          =
env_perl_cpanm_home   = $(abspath cpanm-home)

# how we invoke our ndn-perl; note how things can be tweaked by overriding
# various variable settings.
PERL = PERL5LIB=$(env_perl5lib) \
	   AUTOMATED_TESTING=$(env_automated_testing) \
	   HARNESS_SUBCLASS=$(env_harness_subclass) \
	   HARNESS_OPTIONS=$(env_harness_options) \
	   $(NDN_PERL)

perl_cpanm_home = PERL_CPANM_HOME=$(abspath $(shell mktemp -d $(env_perl_cpanm_home)/workdir.XXXXXXX))

PROVE = $(perl_cpanm_home) $(PERL) $(INC_OURBUILD) $(BINDIR)/prove $(INC_OURBUILD) --harness $(env_harness_subclass)
CPANM = $(perl_cpanm_home) $(PERL) ./cpanm

override_dists := $(shell sed -e '/^\#/d' modules.list.overrides)

tmpfile := $(shell mktemp --tmpdir commit-msg.XXXXXXXX)

# this handles directory recursion, whereas install does not *le sigh*.  add a
# 'v' to have it tell you what it's doing.
INSTALL = cp -pRu

module_deps := $(shell sed -e "/^\#/d" modules.list)
module_targets := $(subst ::,-,$(module_deps))

.PHONY: $(module_targets) show-module-targets
# targets to control our dist cache, etc

.PHONY: archname index ndn-prefix commit-dists rebuild-dpan ndn-libdir \
	refresh-dists refresh-index inject-override-dists \
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

# targets that will get invoked by dh: clean, build, test

######################################################################
# Build our DPAN (aka dists/)

.PHONY: dists dpan refresh-dists refresh-dpan

# cheating here, I know.
dpan: cpanm-home
	rm -rf scratch/ cpanm-home/*
	perl ./cpanm -q $(DPAN_CPANM_OPTS) TAP::Harness::Restricted Module::Build::Tiny Test::More
	$(MAKE) refresh-dists
	$(MAKE) dpan-index
	$(MAKE) dpan-gc
	$(MAKE) dpan-commit-dists

refresh-dists: BUILD_CPANM_OPTS = $(DPAN_CPANM_OPTS)
refresh-dists: CPANM = $(perl_cpanm_home) perl ./cpanm
refresh-dists: $(module_targets)

######################################################################
# DPAN utility targets

.PHONY: dpan-outdated dpan-gc dpan-index dpan-commit-dists \
	inject-override-dists

dpan-gc:
	orepan2-gc dists

dpan-index:
	orepan2-indexer --allow-dev $(DPAN_LOCATION)
	#orepan2-gc $(DPAN_LOCATION)

dpan-outdated:
	@orepan2-audit \
		--darkpan $(DPAN_LOCATION)/modules/02packages.details.txt.gz \
		--cpan http://cpan.metacpan.org/modules/02packages.details.txt \
		--show outdated-modules

dpan-commit-dists:
	# commiting changes to dists/
	git add -A dists/
	echo 'CPAN Updates' >> $(tmpfile)
	echo                >> $(tmpfile)
	git status --porcelain \
		| perl -nE 'chomp; say unless /^[ M\?]/' \
		| grep -v  '02packages' \
		| perl -pE 's!envpan/authors/id/./../!!m' \
		| sed -e 's/\// /' \
		| sed -e 's/^A/ADDED/; s/^D/DELETED/; s/^M/MODIFIED/' \
		| sort -dk3 \
		| column -t \
		| tee -a $(tmpfile)
	git commit --file=$(tmpfile)

# FIXME TODO ummm....  do we need this target invoked when
# building/refreshing the dpan??

# see: https://github.com/tokuhirom/OrePAN2/issues/22
inject-override-dists:
	for i in $(override_dists) ; do orepan2-inject --no-generate-index --allow-dev $$i dists ; done
	orepan2-indexer $(DPAN_LOCATION)

######################################################################
# cleanup, cleanup, everybody everywhere!

.PHONY: clean clean-cpan-home clean-built-diosts clean-test-out

clean: clean-cpanm-home clean-built-dists clean-test-out
	rm -rf scratch/
	rm -rf our-build/ build.sh build-stamp build-tng-stamp

clean-cpanm-home:
	rm -rf $(env_perl_cpanm_home)/*

clean-built-dists:
	rm -rf built-dists

clean-test-out:
	rm -rf test-out/

cpanm-home:
	mkdir -p $(env_perl_cpanm_home)

show-module-targets:
	# $(module_targets)

######################################################################
# build (overall)

.PHONY: build

build: build-stamp

build-stamp: modules.list $(module_targets)
	touch build-stamp

built-dists:
	mkdir -p built-dists

######################################################################
# module build targets, and overrides

TAP-Harness-Restricted: HARNESS_SUBCLASS=
$(module_targets): | cpanm-home built-dists
	$(CPANM) $(BUILD_CPANM_OPTS) $(subst -,::,$@)

#find $(env_perl_cpanm_home)/work -mindepth 2 -maxdepth 2 -type d -exec mv -vf {} built-dists/ \;

######################################################################
# install

.PHONY: install show-installed

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
	find $(DESTDIR) -name '*.pm' -exec chmod 0644 {} \;
	chmod -Rf a+rX,u+w,g-w,o-w $(DESTDIR)

META_DIR = $(OURBUILD)/lib/perl5/$(ARCHNAME)/.meta
installed_json = $(wildcard $(META_DIR)/*/install.json)
test_installed = $(addsuffix .test,$(installed_json))
show_installed = $(addsuffix .show,$(installed_json))

# shortcut function: get the pathname from a .meta/*/install.json
installed_json_to_pathname = `json_xs -e '$$_ = $$_->{pathname}' -t string < $(basename $@)`

$(installed_json):

$(show_installed): $(installed_json)
	@echo `json_xs -e '$$_ = $$_->{pathname}' -t string < $(basename $@)`

show-installed: $(show_installed)

######################################################################
# test (undifferentiated, as of yet)

.PHONY: test retest

retest: clean-test-out
	$(MAKE) test

test_output_dir = test-out
test_output     = $(test_output_dir)/$(lastword $(strip $(subst /, ,$(notdir $@))))

# test all sources -- might be dupes, but that's OK
test_dirs = $(shell find $(env_perl_cpanm_home)/ -mindepth 4 -maxdepth 4 -type d)

show-test-dirs:
	# $(test_dirs)

prove_files = $@/t
prove_opts  = -br
test_cmd = $(if $(realpath $@/Build), ./Build test, make test)

test: env_perl5lib = ../../../../../our-build/lib/perl5
test: $(test_dirs)
test: OURBUILD := $(abspath our-build/)
$(test_dirs): test_output_dir = $(abspath test-out)
$(test_dirs): | test-out
	cd $@ && ( HARNESS_SKIP='t/dist/t/01_compile.t' $(PROVE) $(prove_opts) $(notdir $(realpath $(prove_files))) 1>$(test_output) 2>&1 ) || exit 1
	mv $(test_output) $(test_output)-passed
	gzip -f $(test_output)-passed

######################################################################
# test installed packages (old)

test-installed-packages: $(test_installed)

$(test_installed): $(installed_json)
	$(CPANM) $(TEST_CPANM_OPTS) $(installed_json_to_pathname) 2>&1 | tee $(test_output)
	grep -q '^! Testing \S* failed' $(test_output) && ( awk '{ print $$6 }' $(test_output) | xargs cat ; exit 1 ) ||:

######################################################################
# test utility targets

.PHONY: $(test_dirs)
test-out:
	mkdir -p $(test_output_dir)

######################################################################
# Utility targets

.PHONY: update-cpanm

update-cpanm:
	wget -O cpanm https://raw.githubusercontent.com/miyagawa/cpanminus/devel/cpanm
	git commit -m 'Update cpanm' cpanm

######################################################################
# help

.PHONY: help

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
	#
	# Utility targets
	#   update-cpanm   Pull down the latest fatpacked cpanm from github
	#   retest     Reruns 'make test' after obliterating test-out/*
	#
