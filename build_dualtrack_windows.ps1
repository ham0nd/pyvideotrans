param(
    [string]$OutputDir = "dist-dualtrack"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

Write-Host "[1/6] Checking uv..."
if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
    $env:Path = "$env:USERPROFILE\.local\bin;$env:Path"
}

Write-Host "[2/6] Installing Python 3.10..."
uv python install 3.10

Write-Host "[3/6] Static syntax check..."
uv run --python 3.10 python -m compileall -q videotrans/task/taskcfg.py videotrans/task/speech2text.py videotrans/ui/fn_recogn.py videotrans/winform/fn_recogn.py videotrans/util/_dual_track.py

Write-Host "[4/6] Installing dependencies..."
uv sync --python 3.10 --frozen

Write-Host "[5/6] Import smoke tests..."
uv run python -c "from videotrans.task.taskcfg import TaskCfgSTT; c=TaskCfgSTT(dual_track_call=True, me_track=2); assert c.dual_track_call and c.me_track == 2"
uv run python -c "from videotrans.util._dual_track import probe_dual_track, extract_dual_track_16k; print('dual-track imports OK')"
uv run python -c "from videotrans.task.speech2text import SpeechToText; print('SpeechToText import OK')"

Write-Host "[6/6] Building portable Windows launcher..."

$launcher = @'
import subprocess
import sys
from pathlib import Path

def main():
    root = Path(sys.executable).resolve().parent
    pythonw = root / ".venv" / "Scripts" / "pythonw.exe"
    app = root / "sp.py"
    if not pythonw.exists():
        raise SystemExit(f"Missing portable Python: {pythonw}")
    if not app.exists():
        raise SystemExit(f"Missing application entry: {app}")
    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    subprocess.Popen([str(pythonw), str(app)], cwd=str(root), creationflags=creationflags, close_fds=True)

if __name__ == "__main__":
    main()
'@
Set-Content -Path portable_launcher.py -Value $launcher -Encoding UTF8

Remove-Item launcher-dist, launcher-build, $OutputDir -Recurse -Force -ErrorAction SilentlyContinue
$icon = (Resolve-Path "videotrans/styles/icon.ico").Path
uv run pyinstaller portable_launcher.py --onefile --windowed --name pyVideoTrans-DualTrack --icon "$icon" --distpath launcher-dist --workpath launcher-build --specpath launcher-build

$dest = Join-Path $OutputDir "pyVideoTrans-DualTrack"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "launcher-dist/pyVideoTrans-DualTrack.exe" $dest
Copy-Item "sp.py","cli.py","webui.py","pyproject.toml","uv.lock" $dest
Copy-Item "videotrans" $dest -Recurse
if (Test-Path "ffmpeg") { Copy-Item "ffmpeg" $dest -Recurse }
Copy-Item ".venv" (Join-Path $dest ".venv") -Recurse

$note = @'
双轨通话魔改版

启动：双击 pyVideoTrans-DualTrack.exe

在“语音识别”窗口：
1. 选择通话录音
2. 勾选“双轨通话”
3. 选择“轨道1=我”或“轨道2=我”
4. 勾选“插入说话人”
5. 开始识别

程序支持：
- 两个独立 Audio Stream
- 单个 Stereo/多声道音轨的前两个声道
- 两路分别识别并按时间戳合并
- 输出 [我] / [对方]
- 双方同时讲话时保留两边字幕
'@
Set-Content -Path (Join-Path $dest "双轨通话说明.txt") -Value $note -Encoding UTF8

$archive = Join-Path $OutputDir "pyVideoTrans-DualTrack-Windows-v4.14.7z"
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    7z a -t7z -mx=5 -m0=lzma2 -ms=on $archive "$dest\*"
    Write-Host "Build complete: $archive"
} else {
    $zip = Join-Path $OutputDir "pyVideoTrans-DualTrack-Windows-v4.14.zip"
    Compress-Archive -Path "$dest\*" -DestinationPath $zip -CompressionLevel Optimal
    Write-Host "Build complete: $zip"
}
