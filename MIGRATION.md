# Repository Restructure Notes

This repo was restructured into a monorepo layout.

## New layout (high level)

- Migration.Toolkit/ contains the Migration Toolkit suite (modules under Migration.Toolkit/src/)
- Identity.Security.Assessment.Toolkit/ contains the Identity Security Assessment toolkit

## Common path changes

- ./src  -> ./Migration.Toolkit/src
- ./docs -> ./Migration.Toolkit/docs
- ./build -> ./Migration.Toolkit/build
- ./samples -> ./Migration.Toolkit/samples

If you had local clones:
- Old repo URL should redirect, but it’s recommended to update your remote:
  git remote set-url origin <new_repo_url>
