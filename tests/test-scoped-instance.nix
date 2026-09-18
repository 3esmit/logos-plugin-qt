# Runtime regression for explicit module-instance routing. The overloads must
# remain additive: the default client path and each explicit target instance
# get distinct cache entries and registry endpoints.
{ pkgs, qtHost }:

pkgs.stdenv.mkDerivation {
  pname = "logos-qt-host-scoped-instance-test";
  version = "0.1.0";

  dontUnpack = true;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.ninja
    pkgs.pkg-config
    pkgs.qt6.wrapQtAppsNoGuiHook
  ];

  buildInputs = [
    pkgs.qt6.qtbase
    pkgs.qt6.qtremoteobjects
    pkgs.boost
    pkgs.openssl
    pkgs.nlohmann_json
    qtHost
  ];

  dontUseCmakeConfigure = true;

  buildPhase = ''
    runHook preBuild
    mkdir -p work && cd work

    cat > probe.cpp <<'EOF'
    #include "logos_api.h"
    #include "logos_api_client.h"
    #include "logos_api_provider.h"
    #include "logos_mode.h"

    #include <QCoreApplication>
    #include <QString>

    #include <cstdio>

    static int failures = 0;

    static void check(bool ok, const char* what)
    {
        std::printf("%s  %s\n", ok ? "ok  " : "FAIL", what);
        if (!ok) ++failures;
    }

    int main(int argc, char** argv)
    {
        QCoreApplication app(argc, argv);
        LogosModeConfig::setMode(LogosMode::Mock);

        LogosAPI api("origin");
        // Basecamp uses this historical two-argument spelling; keep it
        // source-compatible while adding the instance constructor.
        LogosAPI legacy("legacy", nullptr);
        LogosAPIClient* defaultClient = api.getClient("indexer");
        LogosAPIClient* zone0101 = api.getClient("indexer", "zone_0101");
        LogosAPIClient* zone8888 = api.getClient("indexer", "zone_8888");

        check(defaultClient != nullptr, "default client is created");
        check(zone0101 != nullptr, "first scoped client is created");
        check(zone8888 != nullptr, "second scoped client is created");
        check(defaultClient != zone0101, "default and scoped clients do not alias");
        check(zone0101 != zone8888, "different scoped clients do not alias");
        check(defaultClient == api.getClient("indexer", QString{}),
              "empty instance ID preserves the default cache entry");
        check(zone0101->registryUrl() ==
                  QStringLiteral("local:logos_indexer_zone_0101"),
              "first scoped client uses its explicit registry endpoint");
        check(zone8888->registryUrl() ==
                  QStringLiteral("local:logos_indexer_zone_8888"),
              "second scoped client uses its explicit registry endpoint");

        LogosAPI first("indexer", QStringLiteral("zone_0101"));
        LogosAPI second("indexer", QStringLiteral("zone_8888"));
        check(first.getProvider()->registryUrl() ==
                  QStringLiteral("local:logos_indexer_zone_0101"),
              "scoped provider publishes the first endpoint");
        check(second.getProvider()->registryUrl() ==
                  QStringLiteral("local:logos_indexer_zone_8888"),
              "scoped provider publishes the second endpoint");

        if (failures) {
            std::printf("\n%d assertion(s) failed\n", failures);
            return 1;
        }
        std::printf("\nall assertions passed\n");
        return 0;
    }
    EOF

    cat > CMakeLists.txt <<'EOF'
    cmake_minimum_required(VERSION 3.14)
    project(LogosScopedInstanceProbe CXX)
    set(CMAKE_CXX_STANDARD 17)
    set(CMAKE_CXX_STANDARD_REQUIRED ON)

    find_package(Qt6 REQUIRED COMPONENTS Core RemoteObjects)
    find_package(logos-qt-host REQUIRED)

    add_executable(probe probe.cpp)
    target_link_libraries(probe PRIVATE
      logos-qt-host::logos_qt_host
      Qt6::Core Qt6::RemoteObjects)
    EOF

    cmake -S . -B build -GNinja
    cmake --build build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    export XDG_RUNTIME_DIR=$TMPDIR
    ./build/probe
    touch $out
    runHook postInstall
  '';

  dontFixup = true;
}
