
# change this to "our" perl; but for now...
#PERL = $(/opt/ndn-perl/bin/perl)
PERL        := PERL5LIB="" PERL_CPANM_OPT="" /opt/ndn-perl/bin/perl
PERL_PREFIX := $(shell $(PERL) -MConfig -E 'say $$Config{prefix}')

# this should be changed to 'Task::NDN' or the like
PRIMARY_DIST := Moose
DPAN_BUILD_DISTS := $(PRIMARY_DIST) Module::Build
# if we want to be using a DPAN external to this repo, too
CPAN_MIRROR  := 'https://stratopan.com/rsrchboy/Test/master'
HARNESS_OPTIONS :=
# we may want to set this to TAP::Harness::Restricted
HARNESS_SUBCLASS :=
BUILD_CPANM_OPTS := -q --from file://`pwd`/dists/

# our build target
OURBUILD := our-build
ARCHNAME := $(shell $(PERL) -MConfig -E 'say $$Config{archname}')
INC_OURBUILD := -I $(OURBUILD)/lib/perl5 -I $(OURBUILD)/lib/perl5/$(ARCHNAME)

tmpfile := $(shell tempfile)

# targets to control our dist cache, etc

.PHONY: archname dpan index ndn-prefix commit-dists

# dh will run the default target first, so make this the default!
all: build

archname:
	@echo $(ARCHNAME)

ndn-prefix:
	@echo $(PERL_PREFIX)

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

dists:
	# download dists
	$(PERL) ./cpanm -q \
		--self-contained -L scratch/ --save-dists=dists \
		$(DPAN_BUILD_DISTS)
	$(MAKE) commit-dists

dpan: index

index: dists
	orepan2-indexer ./dists/

# targets that will get invoked by dh: clean, build, test

clean:
	rm -rf our-build/ scratch/

build:
	$(PERL) ./cpanm $(BUILD_CPANM_OPTS) -L $(OURBUILD) $(PRIMARY_DIST)
	# trim the little things...

install:
	mkdir -p $(DESTDIR)/$(PERL_PREFIX)
	mv $(OURBUILD)/* $(DESTDIR)/$(PERL_PREFIX)/
	# clean it all up
	find $(DESTDIR) -empty -name '*.bs' -exec rm -vf {} \;
	find $(DESTDIR) -name '.packlist' -exec rm -vf {} \;
	find $(DESTDIR) -name 'perllocal.pod' -exec rm -vf {} \;
	find $(DESTDIR) -empty -type d -exec rmdir {} \;

test:
	# no-op, already done in build

