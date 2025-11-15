---
title: Testing Nix Flake Templates That Are Already Working Examples
date: 2025-11-15
categories: [Nix, Development]
tags: [nix, flakes, nixos, templates, testing]
---

> **Note:** This post was written with assistance from Claude AI.

## The Problem

When maintaining Nix flake templates, how do you ensure they actually work? Manual testing is tedious and error-prone. We need automated verification that templates work correctly.

## Two Approaches to Template Testing

### Approach 1: Testing the Initialization Workflow

The traditional approach simulates the user experience with `nix flake init`:

```nix
checks.template-test = pkgs.runCommand "test-init" {
  nativeBuildInputs = [ pkgs.nix ];
} ''
  nix flake init -t ${self}#my-template
  nix build
  # verify output...
'';
```

**Best for:** Minimal skeleton templates that need initialization-time setup.

**Challenges:** Requires network access in sandbox, complex setup, redundant if templates already work.

### Approach 2: Direct Validation (Our Solution)

When templates are **already complete working examples** with their own validation, we can directly import and run those checks.

**Best for:** Templates that:
- Include working example code (like `main.tex` for LaTeX)
- Already have their own validation checks
- Serve as both starter code and documentation

This is what we implemented for [flake-templates](https://github.com/hukaidong/flake-templates).

## Our Solution

### Architecture

```
flake-templates/
├── flake.nix              # Root flake
├── latexmk/               # Template (working example)
│   ├── flake.nix          # Has checks.build
│   └── main.tex           # Example document
└── tests/
    ├── default.nix        # Combines all checks
    └── latexmk-checks.nix # Import latexmk's check
```

**Key insight:** Each template includes validation, we just import and run it.

### Implementation

**Step 1:** Template includes its own check

```nix
# latexmk/flake.nix
{
  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      packages.default = /* build PDF */;
      
      checks.build = pkgs.runCommand "check-build" {} ''
        # Verify PDF generated and valid
        built=${packages.default}
        [ -f "$built/main.pdf" ] || exit 1
        file "$built/main.pdf" | grep -q "PDF" || exit 1
        touch $out
      '';
    });
}
```

**Step 2:** Import template's check from root repository

```nix
# tests/latexmk-checks.nix
{ nixpkgs, flake-utils, ... }:
let
  # Evaluate template flake directly
  latexmkFlake = (import ../latexmk/flake.nix).outputs {
    self.outPath = ../latexmk;
    inherit nixpkgs flake-utils;
  };
in
flake-utils.lib.eachDefaultSystem (system: {
  checks.latexmk-template = latexmkFlake.checks.${system}.build;
})
```

**Step 3:** Combine all template checks

```nix
# tests/default.nix
inputs:
inputs.flake-utils.lib.meld inputs [
  ./latexmk-checks.nix
  # Add more as needed
]
```

**Step 4:** Root flake imports tests

```nix
# flake.nix
{
  outputs = { self, nixpkgs, flake-utils }:
    {
      templates.latexmk = { path = ./latexmk; ... };
    }
    // import ./tests { inherit self nixpkgs flake-utils; };
}
```

## Usage

```bash
# Run all template checks
nix flake check

# Test individual template
cd latexmk && nix flake check
```

## Adding New Templates

1. Create template with its own `checks`
2. Create `tests/<template>-checks.nix` (copy and modify existing)
3. Add to `tests/default.nix` meld list

That's it—three simple steps.

## When to Use This Approach

**Use direct validation when:**
- ✅ Templates are complete working examples
- ✅ Templates already include validation logic
- ✅ You want to avoid duplicating test code

**Use isolated environment testing when:**
- ❌ Templates are just minimal skeletons
- ❌ You need to test the initialization workflow
- ❌ Templates require setup during initialization

## Key Benefits

- **Reuses existing validation:** No duplicate test logic
- **Modular:** Each template's checks are independent
- **Scalable:** Adding templates is straightforward
- **Automated:** Single command runs all checks

## Conclusion

For templates that are already complete, self-validating examples, direct validation is simpler and more maintainable than testing the initialization ceremony. The key is recognizing when templates already have what you need to test.

This pattern works well when:
1. Templates are minimal working examples, not skeletons
2. Templates already validate their outputs
3. Testing template content matters more than initialization process

For skeleton templates, stick with the traditional isolated environment approach.

## Resources

- [My flake-templates repository](https://github.com/hukaidong/flake-templates)
- [Nix Flakes documentation](https://nixos.wiki/wiki/Flakes)
- [flake-utils](https://github.com/numtide/flake-utils)
