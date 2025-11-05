---
title: Pinning Python to a Specific Patch Version in Nix
date: 2025-11-05 12:00:00 -0500
categories: [Nix, Development]
tags: [nix, python, nixos, flakes, overlay, reproducibility]
---

> **Note:** This post was written with assistance from Claude AI.
{: .prompt-info }

> **Warning:** Using a Python overlay to pin a specific version will cause **cache mismatches**. Since your Python version differs from nixpkgs, most Python packages and dependencies will need to be **recompiled from source** rather than using binary cache. This significantly increases build times. Only use this approach when you absolutely need a specific patch version.
{: .prompt-warning }

## The Problem

When working with Nix, you typically get the latest patch version of Python that's available in nixpkgs. While this is usually fine, there are scenarios where you need a specific patch version:

- **Reproducibility**: Ensuring exact environment matches across development and production
- **Compatibility**: Some packages or libraries may have issues with newer patch versions
- **Research environments**: PhD research often requires pinned versions for reproducible results
- **Debugging**: Isolating issues that only occur in specific Python versions

For example, nixos-unstable currently ships Python 3.11.14, but what if your project specifically requires 3.11.11?

## Why Not Just Override `src`?

The naive approach might be to simply override the `src` attribute of the Python derivation. However, this causes subtle misalignments that can break your build:

### 1. Version-Derived Paths Don't Match
The CPython build uses `sourceVersion` to construct paths:
```nix
libPrefix = "python${pythonVersion}";
sitePackages = "lib/${libPrefix}/site-packages";
```

If `sourceVersion` says 3.11.14 but you're building 3.11.11, internal paths will be inconsistent.

### 2. Version-Conditional Patches Fail
The nixpkgs Python build applies patches conditionally based on version:
```nix
++ optionals (pythonOlder "3.13") [
  ./virtualenv-permissions.patch
]
```

Wrong version metadata means patches may apply incorrectly or fail entirely.

### 3. Passthru Attributes Are Wrong
Dependent packages will see the wrong version through `pkgs.python311.version`, causing confusion in the ecosystem.

The root issue: **`sourceVersion` is the source of truth** for all version-dependent build logic, not just the source URL.

## The Solution: Using `callPackage` with Custom Parameters

The correct approach is to use `callPackage` with the cpython derivation directly, providing the exact `sourceVersion`, `hash`, and `passthruFun` parameters.

### Step 1: Create a Flake with Overlay

```nix
{
  description = "Custom Python version using callPackage";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # Define overlay (system-independent)
      pythonOverlay = final: prev: {
        _pythonPassthruFun = import "${prev.path}/pkgs/development/interpreters/python/passthrufun.nix" {
          inherit (prev) __splicedPackages callPackage config db lib 
                         makeScopeWithSplicing' pythonPackagesExtensions stdenv;
        };

        python311 = prev.callPackage "${prev.path}/pkgs/development/interpreters/python/cpython" {
          self = final.python311;
          passthruFun = final._pythonPassthruFun;
          
          sourceVersion = {
            major = "3";
            minor = "11";
            patch = "11";
            suffix = "";
          };
          
          hash = "sha256-Kpkgx6DNI23jNkTtmAoTy7whBYv9xSj+u2CBV17XO+M=";
        };

        python3 = final.python311;
      };
    in
    {
      overlays.default = pythonOverlay;
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ pythonOverlay ];
        };
      in
      {
        packages = {
          default = pkgs.python311;
          python311 = pkgs.python311;
        };

        checks = {
          python-version-check = pkgs.runCommand "check-python-version" {
            buildInputs = [ pkgs.python311 ];
          } ''
            expected="3.11.11"
            version=$(python --version 2>&1 | cut -d' ' -f2)
            [ "$version" = "$expected" ] || {
              echo "Version mismatch: expected $expected, got $version" >&2
              exit 1
            }
            python -c "import sys; assert sys.version_info[:3] == (3, 11, 11)"
            [ "${pkgs.python311.version}" = "$expected" ] || exit 1
            touch $out
          '';
        };
      }
    );
}
```

### Step 2: Get the Source Hash

```bash
nix-prefetch-url https://www.python.org/ftp/python/3.11.11/Python-3.11.11.tar.xz
```

### Step 3: Verify the Version

```bash
nix flake check  # Runs the version check
nix run          # Test the Python interpreter
python --version # Should output: Python 3.11.11
```

## Key Components Explained

### The Overlay Structure

```nix
let
  pythonOverlay = final: prev: { ... };
in
{
  overlays.default = pythonOverlay;
}
// flake-utils.lib.eachDefaultSystem (...)
```

This pattern separates system-independent (overlay) from system-dependent (packages, checks) outputs, making the overlay reusable across different systems and configurations.

### The `_pythonPassthruFun`

```nix
_pythonPassthruFun = import "${prev.path}/pkgs/development/interpreters/python/passthrufun.nix" {
  inherit (prev) __splicedPackages callPackage config db lib ...;
};
```

This function provides the passthru attributes that Python packages expect, like `pythonVersion`, `sitePackages`, etc.

### Version Validation

The check ensures three critical invariants:
1. Runtime version matches (`python --version`)
2. Internal version info matches (`sys.version_info`)
3. Derivation attribute matches (`pkgs.python311.version`)

## Usage in Other Projects

Once you have this flake, you can use it in other projects:

```nix
{
  inputs.custom-python.url = "path:./python-overlay";
  
  outputs = { nixpkgs, custom-python, ... }: {
    devShells.x86_64-linux.default = 
      let
        pkgs = import nixpkgs {
          system = "x86_64-linux";
          overlays = [ custom-python.overlays.default ];
        };
      in
      pkgs.mkShell {
        buildInputs = [ pkgs.python311 ];
      };
  };
}
```

## Conclusion

Pinning Python to a specific patch version in Nix requires more than just overriding the source. By using `callPackage` with explicit `sourceVersion` and `hash` parameters, we ensure that all version-dependent build logic remains consistent. This approach:

- ✅ Maintains version consistency across all build phases
- ✅ Ensures patches apply correctly
- ✅ Provides accurate version metadata to dependent packages
- ✅ Creates a reusable overlay for multiple projects
- ✅ Includes verification through automated checks

**However, be aware of the trade-offs:**
- ⚠️ Binary cache incompatibility - most packages will rebuild from source
- ⚠️ Significantly longer build times (especially for packages with C extensions)
- ⚠️ Increased disk space usage from building dependencies

This pattern is particularly valuable for research environments, where reproducibility is paramount, and for production systems that require strict version control. The build time cost is often acceptable when exact reproducibility is more important than convenience.

Consider alternatives before using this approach:
- Can you use the nixpkgs version and test for compatibility?
- Can you use `pyenv` or `conda` within a Nix shell for Python-specific version management?
- Is the patch version difference actually causing issues, or just a nice-to-have?

Use Python overlays when you have a concrete, unavoidable requirement for a specific patch version.

## Resources

- [nixpkgs CPython derivation](https://github.com/NixOS/nixpkgs/blob/master/pkgs/development/interpreters/python/cpython/default.nix)
- [Nix Flakes documentation](https://nixos.wiki/wiki/Flakes)
- [Python release downloads](https://www.python.org/downloads/)
