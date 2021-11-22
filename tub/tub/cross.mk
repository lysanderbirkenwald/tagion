# machine-vendor-operatingsystem
TRIPLET ?= $(ARCH)-unknown-$(OS)

TRIPLET_SPACED := ${subst -, ,$(TRIPLET)}

# If TRIPLET specified with 2 words
# fill the VENDOR as unknown
CROSS_ARCH := ${word 1, $(TRIPLET_SPACED)}
ifeq (${words $(TRIPLET_SPACED)},2)
CROSS_VENDOR := unknown
CROSS_OS := ${word 2, $(TRIPLET_SPACED)}
else
CROSS_VENDOR := ${word 2, $(TRIPLET_SPACED)}
CROSS_OS := ${word 3, $(TRIPLET_SPACED)}
endif

CROSS_ENABLED := 1

# If same as host - reset vars not to trigger
# cross-compilation logic
ifeq ($(CROSS_ARCH),$(ARCH))
ifeq ($(CROSS_OS),$(OS))
CROSS_ARCH :=
CROSS_VENDOR :=
CROSS_OS :=
CROSS_ENABLED :=
endif
endif

MTRIPLE := $(CROSS_ARCH)-$(CROSS_VENDOR)-$(CROSS_OS)
ifeq ($(MTRIPLE),--)
MTRIPLE := $(TRIPLET)
endif

# IOS
XCODE_ROOT := ${shell xcode-select -print-path}
XCODE_SIMULATOR_SDK = $(XCODE_ROOT)/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator$(IPHONE_SDKVERSION).sdk
XCODE_DEVICE_SDK = $(XCODE_ROOT)/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS$(IPHONE_SDKVERSION).sdk
CROSS_SYSROOT=$(XCODE_SIMULATOR_SDK)

MAKE_ENV += env-cross
env-cross:
	$(call log.header, env :: cross)
	$(call log.kvp, MTRIPLE, $(MTRIPLE))
	$(call log.kvp, CROSS_ENABLED, $(CROSS_ENABLED))
	$(call log.kvp, CROSS_ARCH, $(CROSS_ARCH))
	$(call log.kvp, CROSS_VENDOR, $(CROSS_VENDOR))
	$(call log.kvp, CROSS_OS, $(CROSS_OS))
	$(call log.separator)
	$(call log.kvp, CROSS_SYSROOT, $(CROSS_SYSROOT))
	$(call log.subheader, android)
	$(call log.kvp, ANDROID_ROOT, $(ANDROID_ROOT))
	$(call log.kvp, ANDROID_NDK, $(ANDROID_NDK))
	$(call log.subheader, ios)
	$(call log.kvp, XCODE_ROOT, $(XCODE_ROOT))
	$(call log.kvp, XCODE_SIMULATOR_SDK, $(XCODE_SIMULATOR_SDK))
	$(call log.kvp, XCODE_DEVICE_SDK, $(XCODE_DEVICE_SDK))
	$(call log.close)