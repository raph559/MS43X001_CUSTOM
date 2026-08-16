"""Build protocol 3 without replacing the retained protocol 2 artifacts."""
import os
import build_live_overlay as build

build.SOURCE = os.path.join(build.REPO, 'patches', 'live_overlay_v3.asm')
build.DEFAULT_OUT = os.path.join(build.REPO, 'build', 'CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V3.bin')
build.DEFAULT_FIXTURE = os.path.join(build.REPO, 'sim', 'tests', 'Ms43Sim.Tests', 'fixtures', 'live_overlay_v3.hex')

if __name__ == '__main__':
    build.main()
