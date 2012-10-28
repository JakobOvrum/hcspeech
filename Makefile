BUILD ?= release
MODEL ?= $(shell getconf LONG_BIT)

UNAME ?= $(shell uname)

ifeq ($(UNAME), Linux)
	DLL =$1.so
	LIB =lib$1.a
	PATHSEP=/
else # Assume Windows
	DLL =$1.dll
	LIB =$1.lib
	PATHSEP=$(strip \)
	EXTRAS = "visuald\hcspeech.def" "speech4d\lib\sapi.lib" "ole32.lib"
endif

ifneq ($(MODEL), 32)
	ifneq ($(MODEL), 64)
		$(error Unsupported architecture: $(MODEL))
	endif
endif

ifneq ($(BUILD), debug)
	ifneq ($(BUILD), release)
		$(error Unknown build mode: $(BUILD))
	endif
endif

DFLAGS = -w -wi -property -Ixchatd -Ispeech4d -m$(MODEL)

ifeq ($(BUILD), release)
	DFLAGS += -release -O -inline -noboundscheck
else
	DFLAGS += -debug -gc
	DEBUGSUFFIX = -d
endif

ifeq ($(MODEL), 32)
	OUTDIR = bin32
	LIBDIR = lib32
else
	OUTDIR = bin
	LIBDIR = lib
endif

HCSPEECH_OUTPUT = $(OUTDIR)$(PATHSEP)$(call DLL,hcspeech$(DEBUGSUFFIX))

HCSPEECH_LIBS = xchatd$(PATHSEP)$(LIBDIR)$(PATHSEP)$(call LIB,xchatd$(DEBUGSUFFIX)) \
                speech4d$(PATHSEP)$(LIBDIR)$(PATHSEP)$(call LIB,speech4d-sapi$(DEBUGSUFFIX))

HCSPEECH_SOURCES = hcspeech/hcspeech.d

all: $(HCSPEECH_OUTPUT)

.PHONY : clean xchatd speech4d

clean:
	rm $(HCSPEECH_OUTPUT)

xchatd:
	cd xchatd; $(MAKE) -f Makefile.gdc

speech4d:
	cd speech4d; $(MAKE) -f Makefile.gdc

$(HCSPEECH_OUTPUT): xchatd speech4d $(HCSPEECH_SOURCES)
	dmd $(DFLAGS) -of"$@" $(HCSPEECH_SOURCES) $(HCSPEECH_LIBS) $(EXTRAS)
