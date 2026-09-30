"""Copy the repository's scripts into a mission file.

DCS keeps its own copy of every DO SCRIPT FILE inside the .miz
(l10n/DEFAULT/<file>), taken when the mission is saved in the editor: after a
script is edited, the mission keeps running the old copy until the file is
picked again in its trigger and the mission saved. This does the same
without the editor, for every script the mission already carries and the
repository has; everything else in the archive is copied unchanged.

    python tools/embed_scripts.py                      # the repository's mission
    python tools/embed_scripts.py "My mission.miz"     # another one

Standard library only.
"""
import os
import sys
import tempfile
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_MIZ = os.path.join(REPO, 'Op. White Wyverns Training.miz')


def embed(miz):
    """Refresh the scripts inside `miz`; returns the names that changed."""
    with zipfile.ZipFile(miz) as z:
        infos = z.infolist()
        data = {i.filename: z.read(i.filename) for i in infos}
    changed = []
    for name in data:
        if name.startswith('l10n/DEFAULT/') and name.endswith('.lua'):
            src = os.path.join(REPO, os.path.basename(name))
            if os.path.isfile(src):
                with open(src, 'rb') as f:
                    new = f.read()
                if new != data[name]:
                    data[name] = new
                    changed.append(os.path.basename(name))
    if not changed:
        return changed
    # Written next to the mission and swapped in at the end: a failure half-way
    # leaves the original untouched.
    fd, tmp = tempfile.mkstemp(suffix='.miz', dir=os.path.dirname(os.path.abspath(miz)))
    os.close(fd)
    try:
        with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_DEFLATED) as out:
            for i in infos:
                zi = zipfile.ZipInfo(i.filename, date_time=i.date_time)
                zi.compress_type = zipfile.ZIP_DEFLATED
                out.writestr(zi, data[i.filename])
        os.replace(tmp, miz)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return changed


if __name__ == '__main__':
    target = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MIZ
    done = embed(target)
    print(('updated: ' + ', '.join(done)) if done else 'already up to date')
