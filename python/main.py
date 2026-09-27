import json
import traceback

if __name__ == "__main__":
    "wrap entrypoint for cleaner reporting of missing modules"

    try:
        from run import main
        main()
    except ModuleNotFoundError as e:
        msg = {"type": "startup_failed", "message": str(e)}
        print(json.dumps(msg))
    except:
        tb = traceback.format_exc()
        print(tb)
