# Splattrack

Automated photogrammetry pipeline, creating 3D motion tracking and 3D Gaussian Splats from source video, using [COLMAP](https://github.com/colmap/colmap/) and [Brush](https://github.com/ArthurBrussee/brush), in a self-contained Docker container, with GPU (Nvidia) support.

Based on [polyfjord's Windows workflow](https://gist.github.com/polyfjord/fc22f22770cd4dd365bb90db67a4f2dc) and [ghxst0000's colmap-glomap-autotracker](https://github.com/ghxst0000/colmap-glomap-autotracker).

## Usage

### First time setup

The image is not on Docker Hub yet, so you will have to build it, luckily it is a straightforward task.

Build the container:
```bash
cd docker/splattrack
docker compose build
```

This process takes about 50 minutes (on an Intel Core i7-1185G7), and uses about 25 GiB of disk space.

Copy and edit the settings file:
```bash
cp .env.example .env
```

### Preparing the video files

Place your videos in the `docker/splattrack/workspace/videos` directory.

### Running the pipeline

```bash
cd docker/splattrack
docker compose run --rm splattrack
```

The output will be placed in `docker/splattrack/workspace/scenes`, follwing the structure below:
```
─── workspace
    ├── videos                    - source video files
    └── scenes                    - output and work directory
        └── VID_20260501_121212   - one output directory per video file
            ├── images              - extracted frames
            ├── sparse              - COLMAP motion tracking reconstruction
            └── dataset_exports     - 3D Gaussian Splat
```

The processing consists of several steps, if one fails the whole pipeline stops and continues with the next video file. The progress is saved, a completed step will not be processed again upon retry.

### Settings

The default settings are leaning to more accurate and detailed results, changing them can reduce the processing time significantly, see the [.env.example](docker/splattrack/.env.example) for the details.

Override the default settings in the .env file, or by setting the environment variables when starting the container, e.g.:

```bash
docker compose run -e EXTRACT_FPS=2 -e SEQUENTIAL_OVERLAP=8 --rm splattrack
```

NOTE: if you change any settings and want to reprocess a video, you should delete the corresponding directory under `scenes`, or just the the `*_done` flags of the steps you want to rerun.

## How to use the results

### 3D motion tracking

#### Import into Blender

1. Install the [Blender COLMAP importer](https://github.com/SBCV/Blender-Addon-Photogrammetry-Importer) addon
2. *File* > *Import* > *Colmap (model/workspace)*
3. Check the *Supress Distortion Warnings* checkbox
4. Navigate to `.../workspace/scenes/<video_name>/sparse/`
5. Click *Import*

### 3D Gaussian Splats

#### Use Supersplat

[Supersplat](https://github.com/playcanvas/supersplat) is a browser based 3D Gaussian Splatt editor/viewer/publisher.

You can import it to the [online editor](https://superspl.at/editor), or you can host your own using Docker by the following steps:
```bash
cd docker/supersplat
docker compose up
```

After this the editor should be running on your computer at `http://localhost:3000/`, open it and use it the same way as the online one.

For publishing the splat you would need a Playcanvas account, or you can also export and host it yourself. Use *File* > *Export* > *Viever app...*, choose *ZIP* under *Export type* (HTML creates one single HTML file that contains the splat itself, which leads to a file that might be even several hundred megabytes, this might cause issues and hangs with browsers).

#### Import into Blender

1. Install the [3DGS Render Blender Addon](https://github.com/Kiri-Innovation/3dgs-render-blender-addon) (see notes there for Blender 5.1)
2. ...
3. Click *Import*
