"""Run ``python -m friday_runtime {prepare,laya,wake}``."""

import argparse
from pathlib import Path
import sys

from .protocol import ProtocolError, protocol_stdout


def main() -> int:
    with protocol_stdout() as emit:
        parser = argparse.ArgumentParser(description="Friday local model preparation and JSON-line workers")
        commands = parser.add_subparsers(dest="command", required=True)
        prepare_parser = commands.add_parser("prepare", help="Download pinned local models once")
        prepare_parser.add_argument("--model-root", required=True, type=Path)
        for name in ("laya", "wake"):
            worker_parser = commands.add_parser(name, help="Run the offline " + name + " worker")
            worker_parser.add_argument("--model-dir", required=True, type=Path)
        args = parser.parse_args()
        try:
            if args.command == "prepare":
                from .prepare import prepare_models

                emit(prepare_models(args.model_root))
            elif args.command == "laya":
                from .laya import run_laya

                run_laya(args.model_dir, sys.stdin.buffer, emit)
            else:
                from .wake import run_wake

                run_wake(args.model_dir, sys.stdin.buffer, emit)
        except KeyboardInterrupt:
            return 130
        except BrokenPipeError:
            return 0
        except ProtocolError as error:
            emit({"type": "error", "provider": args.command, "error": str(error)})
            return 1
        except Exception as error:
            # Names help diagnose installed-package failures, while exception
            # messages and tracebacks could expose user text or audio.
            emit({"type": "error", "provider": args.command, "error": "Local runtime failed (" + type(error).__name__ + ")."})
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
