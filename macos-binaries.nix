{ lib, stdenvNoCC, fetchurl, unzip, makeWrapper, fd, ripgrep }:

let
  pins = builtins.fromJSON (builtins.readFile ./macos-binaries.json);
  package = name: executable: format:
    let pin = pins.${name}; in
    stdenvNoCC.mkDerivation {
      pname = name;
      inherit (pin) version;
      src = fetchurl { inherit (pin) url sha256; };
      dontUnpack = true;
      dontFixup = true; # Preserve upstream signatures and the complete release layout.
      nativeBuildInputs = lib.optional (format == "zip") unzip
        ++ lib.optional (name == "pi") makeWrapper;
      installPhase = ''
        runHook preInstall
        release="$out/libexec/${name}"
        mkdir -p "$release" "$out/bin"
        ${if format == "raw" then ''
          cp "$src" "$release/${executable}"
          chmod +x "$release/${executable}"
        '' else if format == "zip" then ''
          unzip -q "$src" -d "$release"
        '' else ''
          tar -xzf "$src" -C "$release"
        ''}
        # Releases may have a versioned top-level directory; keep all resources.
        binary="$(find "$release" -type f -name ${lib.escapeShellArg executable})"
        test -n "$binary" && test -f "$binary" && test -x "$binary"
        ${if name == "pi" then ''
          makeWrapper "$binary" "$out/bin/pi" \
            --prefix PATH : ${lib.makeBinPath [ fd ripgrep ]} \
            --set PI_PACKAGE_DIR "$(dirname "$binary")" \
            --set PI_SKIP_VERSION_CHECK 1 \
            --set PI_TELEMETRY 0
        '' else ''
          ln -s "$binary" "$out/bin/${executable}"
        ''}
        ${lib.optionalString (name == "uv") ''
          ln -s "$(dirname "$binary")/uvx" "$out/bin/uvx"
        ''}
        ${lib.optionalString (name == "pnpm") ''
          cat > "$out/bin/pnpx" <<EOF
#!${stdenvNoCC.shell}
exec "$out/bin/pnpm" dlx "\$@"
EOF
          chmod +x "$out/bin/pnpx"
        ''}
        runHook postInstall
      '';
      passthru.binaryRelease = true;
      meta = {
        mainProgram = executable;
        platforms = [ "aarch64-darwin" ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      };
    };
in {
  pnpm = package "pnpm" "pnpm" "tar";
  uv = package "uv" "uv" "tar";
  sing-box = package "sing-box" "sing-box" "tar";
  bws = package "bws" "bws" "zip";
  herdr = package "herdr" "herdr" "raw";
  kimi-code = package "kimi-code" "kimi" "tar";
  pi = package "pi" "pi" "tar";
}
