NAME := Ksign
PLATFORM := iphoneos
SCHEMES := Ksign
TMP := $(TMPDIR)/$(NAME)
STAGE := $(TMP)/stage
APP := $(TMP)/Build/Products/Release-$(PLATFORM)

.PHONY: all clean $(SCHEMES)

all: $(SCHEMES)

clean:
	rm -rf "$(TMP)"
	rm -rf packages
	rm -rf Payload

deps:
	rm -rf deps || true
	mkdir -p deps
	curl -L -o deps/server.leaf https://backloop.dev/backloop.dev-cert.crt || true
	# The leaf *and* the CA above it. `backloop.dev-cert.crt` is the leaf on
	# its own, and it is issued by an intermediate no device carries, so a
	# server handing over only that is one nothing can verify: iOS drops the
	# manifest fetch behind `itms-services://` without a word and the install
	# never comes up.
	curl -L -o deps/server.ca https://backloop.dev/backloop.dev-ca.crt || true
	cat deps/server.leaf deps/server.ca > deps/server.crt 2>/dev/null || true
	rm -f deps/server.leaf deps/server.ca
	curl -L -o deps/server.key1 https://backloop.dev/backloop.dev-key.part1.pem || true
	curl -L -o deps/server.key2 https://backloop.dev/backloop.dev-key.part2.pem || true
	cat deps/server.key1 deps/server.key2 > deps/server.pem 2>/dev/null || true
	rm -f deps/server.key1 deps/server.key2
	# A host, not the wildcard the certificate is issued to: `*.backloop.dev`
	# resolves nowhere, and the install manifest has to be fetched from a name
	# the device can actually reach. Every label under it points at 127.0.0.1.
	echo "ksign.backloop.dev" > deps/commonName.txt

$(SCHEMES): deps
	xcodebuild \
	    -project Ksign.xcodeproj \
	    -scheme "$@" \
	    -configuration Release \
	    -arch arm64 \
	    -sdk $(PLATFORM) \
	    -derivedDataPath $(TMP) \
	    -skipPackagePluginValidation \
	    CODE_SIGNING_ALLOWED=NO \
	    ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES=NO

	rm -rf Payload
	rm -rf "$(STAGE)/"
	mkdir -p "$(STAGE)/Payload"

	mv "$(APP)/$@.app" "$(STAGE)/Payload/$@.app"

	chmod -R 0755 "$(STAGE)/Payload/$@.app"
	codesign --force --sign - --timestamp=none "$(STAGE)/Payload/$@.app"

	cp deps/* "$(STAGE)/Payload/$@.app/" || true

	rm -rf "$(STAGE)/Payload/$@.app/_CodeSignature"
	ln -sf "$(STAGE)/Payload" Payload
	
	mkdir -p packages
	zip -r9 "packages/$@.ipa" Payload