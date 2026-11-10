# pols checkout

Checks out your repository from a Git mirror that stays on the
[pols](https://pols.so) runner cache between jobs. The first job of a
repository clones it once; every job after that fetches only the commits
pushed since, and the working copy reads its objects from the mirror instead
of copying them.

Replace `actions/checkout` with it:

```yaml
jobs:
  test:
    runs-on: pols-small
    steps:
      - uses: PEWEO/pols-checkout@v1
```

It takes the inputs of `actions/checkout` (`repository`, `ref`, `token`,
`path`, `fetch-depth`, `fetch-tags`, `clean`, `persist-credentials`, ...) and
gives its outputs (`ref`, `commit`), plus `cached`: whether the checkout came
from the cache.

## How it works

On a pols runner (`runs-on: pols-<size>`), each job gets a copy of its
repository's cache disk, mounted at `/mnt/pols-cache`, and the runner's
environment names a status file that says so. This action waits for it (up
to `cache-wait` seconds, 60 by default), keeps a bare mirror of the
repository at `/mnt/pols-cache/git/<owner>/<name>.git`, fetches every branch
and tag into it, and checks out the job's commit from it.

- A job's copy becomes the cache only when the job succeeds. Jobs of a pull
  request from a fork read the cache but never write to it.
- The mirror has the whole history, so `fetch-depth` makes no difference to
  speed; with `fetch-depth: 0` or `fetch-tags: true` the working copy sees
  every branch or tag, as with `actions/checkout`.
- `ssh-key`, `filter`, `sparse-checkout`, `lfs` and `submodules` hand the
  checkout to `actions/checkout`, as does a cached checkout that fails.
- Anywhere else (GitHub's runners, your own) it is `actions/checkout`, with
  the same inputs.

## License

MIT
