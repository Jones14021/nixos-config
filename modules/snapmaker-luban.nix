# home/jonas.nix contains the fix for non-writeable Snapmaker Luban
# config directory in Home Manager user environment

{ pkgs, ... }:
let 
    version = "4.15.0";
in
{
    nixpkgs.overlays = [
        (final: prev: {
            snapmaker-luban = prev.snapmaker-luban.overrideAttrs (old: {
                # Luban replaces its workers' environment, so pass the font filter
                # through explicitly. Store fonts are read-only; keep copies writable
                # before and after each overwrite so font initialization can finish.
                postInstall = (old.postInstall or "") + ''
                    substituteInPlace "$out/opt/resources/app/src/server/index.js" \
                      --replace-fail 'forkOpts:{env:{Tmpdir:K.a.tmpDir,fontDir:K.a.fontDir}}' 'forkOpts:{env:{Tmpdir:K.a.tmpDir,fontDir:K.a.fontDir,FONTCONFIG_FILE:process.env.FONTCONFIG_FILE}}' \
                      --replace-fail 'n.statSync(a).isFile()&&n.copyFileSync(a,c)' 'n.statSync(a).isFile()&&(n.existsSync(c)&&n.chmodSync(c,420),n.copyFileSync(a,c),n.chmodSync(c,420))'
                '';
                # The bundled font scanner crashes on variable-font entries with
                # missing metadata. Hide those entries only from Luban, and use XWayland.
                preInstall = (old.preInstall or "") + ''
                    gappsWrapperArgs+=(--set FONTCONFIG_FILE ${final.writeText "luban-fonts.conf" ''
                        <?xml version="1.0"?>
                        <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
                        <fontconfig>
                          <include>/etc/fonts/fonts.conf</include>
                          <selectfont>
                            <rejectfont>
                              <pattern><patelt name="variable"><bool>true</bool></patelt></pattern>
                            </rejectfont>
                          </selectfont>
                        </fontconfig>
                    ''} --add-flags --ozone-platform=x11)
                '';
            });
        })
    ];

    # Optional: pin version
    #nixpkgs.overlays = [
    #    (final: prev: {
    #        snapmaker-luban = prev.snapmaker-luban.overrideAttrs (old: rec {               
    #            src = prev.fetchurl {
    #            url = "https://github.com/Snapmaker/Luban/releases/download/v${version}/snapmaker-luban-${version}-linux-x64.tar.gz";
    #            # put fake sha256 to update: sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=
    #            hash = "sha256-VNIuOsRTS5qsq4IK1G6NSidNNEgziHGTNGvDKwjPO70=";
    #            };
    #        });
    #    })
    #];

    #nixpkgs.config.permittedInsecurePackages = [
    #    "snapmaker-luban-${version}"
    #];
}
