# fnOS NAS Web adapter (Linux amd64 / x86_64)

A Docker Compose adapter for Shalielie v0.7.0, designed for x86_64 fnOS hosts with Docker. It wraps the existing HEIC and Live Photo processing engine in an authenticated, mobile-friendly Web app. **Not an fnOS .fpk package.** See the [full Chinese deployment guide](README.zh-CN.md).

**For a true Live Photo in the iOS Photos library, use the [native iPhone importer](../ios-client/README.md). The Web ZIP output is a compatibility fallback, not native Photos import.**

## Setup

Install Docker/Compose on fnOS and verify the CPU architecture is x86_64.

    git clone https://github.com/Rok1n/Shalielie.git
    cd Shalielie
    git switch feat/fnos-x86-web-live-photo
    cd nas
    cp .env.example .env
    python3 -c "import secrets; print(secrets.token_urlsafe(36))"

Put the resulting random string in nas/.env as SHALIELIE_TOKEN, replacing the placeholder. Do not commit the secret. Then:

    chmod 600 .env
    docker compose -f compose.yaml config --quiet
    docker compose -f compose.yaml up -d --build

Open http://NAS_LAN_IP:8766 on a phone. Enter your secret token and upload an original HEIC. Optionally upload its **matching MOV** to generate a Live Photo HEIC+MOV ZIP. From iOS, a Photos picker may convert a HEIC to JPEG or omit the MOV. Select originals from Files. Downloading a ZIP to Files does **not** automatically restore a Live Photo in Apple Photos.

The Python 3.12 container includes ffmpeg/libx265 and heif-convert. The upstream porter retains source image content and metadata to the extent documented in the main README while necessarily modifying Apple style metadata. This is an experimental workflow; validate output on your actual iPhone/iOS and NAS.

There are no persistent photo volumes, output database or image history. Files occupy temporary container storage while a task runs and are removed after transfer; crash orphans are cleaned up at startup. One job at a time; default request limit 320 MB and process timeout 600 seconds. The Docker image and container itself still consume disk space.

**Security:** the access token is mandatory, but HTTP is not encrypted. Trusted LAN or private VPN use only. Do not expose the raw NAS port directly to the Internet.

## Local transport tests

    pip install -r nas/requirements.txt httpx
    SHALIELIE_TOKEN=only-for-local-tests-1234567890 python -m unittest discover -s nas/tests -v
