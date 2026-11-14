fn main() {
  // The iOS app links libapp.a together with WidgetReload.swift, which defines this
  // symbol; the cdylib cargo also builds never sees that Swift, so let it stay undefined.
  if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("ios") {
    println!("cargo:rustc-cdylib-link-arg=-Wl,-U,_crosspoint_reload_widgets");
  }
  if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
    link_widget_reload();
  }
  // tauri-build only watches tauri.conf.json; the macOS window settings live here.
  println!("cargo:rerun-if-changed=tauri.macos.conf.json");
  tauri_build::build()
}

// macOS: the same WidgetReload.swift as iOS, built into a static library so Rust can
// ask WidgetKit to redraw after writing new widget data.
fn link_widget_reload() {
  use std::process::Command;
  let source = "gen/apple/Sources/crosspoint-sync-app/WidgetReload.swift";
  println!("cargo:rerun-if-changed={source}");
  let out = std::path::PathBuf::from(std::env::var("OUT_DIR").unwrap());
  let arch = match std::env::var("CARGO_CFG_TARGET_ARCH").unwrap().as_str() {
    "aarch64" => "arm64",
    other => other,
  }
  .to_string();
  let target = format!("{arch}-apple-macos11.0");
  let status = Command::new("xcrun")
    .args(["--sdk", "macosx", "swiftc", "-target", &target, "-parse-as-library", "-runtime-compatibility-version", "none", "-static", "-emit-library", "-module-name", "WidgetReload", "-o"])
    .arg(out.join("libwidgetreload.a"))
    .arg(source)
    .status()
    .expect("xcrun swiftc (Xcode command line tools) is required for the macOS build");
  assert!(status.success(), "compiling {source} failed");
  let sdk = Command::new("xcrun").args(["--sdk", "macosx", "--show-sdk-path"]).output().unwrap();
  let sdk = String::from_utf8(sdk.stdout).unwrap();
  println!("cargo:rustc-link-search=native={}", out.display());
  println!("cargo:rustc-link-lib=static=widgetreload");
  println!("cargo:rustc-link-search=native={}/usr/lib/swift", sdk.trim());
  println!("cargo:rustc-link-lib=framework=WidgetKit");
}
