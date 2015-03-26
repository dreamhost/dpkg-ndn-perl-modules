
# change this to "our" perl; but for now...
#PERL = $(/opt/ndn-perl/bin/perl)
PERL        := PERL5LIB="" PERL_CPANM_OPT="" /opt/ndn-perl/bin/perl
PERL_PREFIX := $(shell $(PERL) -MConfig -E 'say $$Config{prefix}')
SITELIB     := $(shell $(PERL) -MConfig -E 'say $$Config{sitelib}')
SITEARCH    := $(shell $(PERL) -MConfig -E 'say $$Config{sitearch}')
ARCHNAME    := $(shell $(PERL) -MConfig -E 'say $$Config{archname}')
BINDIR      := $(shell $(PERL) -MConfig -E 'say $$Config{bindir}')

NDN_LIB := $(SITELIB)
NDN_BIN := $(BINDIR)
NDN_MAN := $(PERL_PREFIX)/man

# this should be changed to 'Task::NDN' or the like
PRIMARY_DIST := Moose
DPAN_BUILD_DISTS := $(PRIMARY_DIST) Module::Build
# if we want to be using a DPAN external to this repo, too
CPAN_MIRROR  := 'https://stratopan.com/rsrchboy/Test/master'
HARNESS_OPTIONS :=
# we may want to set this to TAP::Harness::Restricted
HARNESS_SUBCLASS :=
BUILD_CPANM_OPTS := -q --from file://`pwd`/dists/ \
	--exclude-vendor --man-pages

# our build target
OURBUILD     := our-build
INC_OURBUILD := -I $(OURBUILD)/lib/perl5 -I $(OURBUILD)/lib/perl5/$(ARCHNAME)

tmpfile := $(shell tempfile)

# targets to control our dist cache, etc

.PHONY: archname dpan index ndn-prefix commit-dists rebuild-dpan ndn-libdir

# dh will run the default target first, so make this the default!
all: build

archname:
	@echo $(ARCHNAME)

ndn-prefix:
	@echo $(PERL_PREFIX)

ndn-libdir:
	@echo $(NDN_LIB)

dev-clean: clean
	rm -rf dists/

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

# note we deliberately do *not* set a CPAN mirror here.  This is intentional.
dists:
	# download dists
	$(PERL) ./cpanm -q --exclude-vendor \
		--self-contained -L scratch/ --save-dists=dists \
		$(DPAN_BUILD_DISTS)

dpan: index

index: dists
	orepan2-indexer ./dists/

rebuild-dpan: dev-clean
	$(MAKE) dpan
	$(MAKE) commit-dists

# targets that will get invoked by dh: clean, build, test

clean:
	rm -rf our-build/ scratch/

build:
	$(PERL) ./cpanm $(BUILD_CPANM_OPTS) -L $(OURBUILD) $(PRIMARY_DIST)
	# trim the little things...

install:
	# perl libs...
	mkdir -p $(DESTDIR)/$(NDN_LIB)
	mv $(OURBUILD)/lib/perl5/* $(DESTDIR)/$(NDN_LIB)/
	# scripties, binaries, whatnot...
	mkdir -p $(DESTDIR)/$(NDN_BIN)
	mv $(OURBUILD)/bin/* $(DESTDIR)/$(NDN_BIN)/
	# man pages...
	mkdir -p $(DESTDIR)/$(NDN_MAN)
	mv $(OURBUILD)/man/* $(DESTDIR)/$(NDN_MAN)/*
	# ...and clean it all up.
	find $(DESTDIR) -empty -name '*.bs' -exec rm -vf {} \;
	find $(DESTDIR) -name '.packlist' -exec rm -vf {} \;
	find $(DESTDIR) -name 'perllocal.pod' -exec rm -vf {} \;
	find $(DESTDIR) -empty -type d -delete
	chmod -Rf a+rX,u+w,g-w,o-w $(DESTDIR)

test:
	# no-op, already done in build

