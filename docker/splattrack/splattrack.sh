#!/usr/bin/env bash

set -euo pipefail

# default settings, override via .env or `docker compose run -e EXTRACT_FPS=2 --rm splattrack`
USE_GPU="${USE_GPU:-auto}"
GAUSSIAN_SPLAT="${GAUSSIAN_SPLAT:-true}"
EXTRACT_FPS="${EXTRACT_FPS:-0}"
SIFT_MAX_NUM_FEATURES="${SIFT_MAX_NUM_FEATURES:-8192}"
SIFT_MAX_IMAGE_SIZE="${SIFT_MAX_IMAGE_SIZE:-3200}"
SIFT_NUM_THREADS="${SIFT_NUM_THREADS:-4}"
SEQUENTIAL_OVERLAP="${SEQUENTIAL_OVERLAP:-15}"
BRUSH_TRAIN_ITERS="${BRUSH_TRAIN_ITERS:-30000}"

VIDEOS_DIR="/workspace/videos"
SCENES_DIR="/workspace/scenes"

NC="\033[0m"
RED="\033[1;31m"
BLUE="\033[1;34m"
WHITE="\033[1;37m"

_echo_title() {
	echo ""
	echo -e "${BLUE}$@${NC}"
}

_echo_step() {
	echo ""
	echo -e "${WHITE}$@${NC}"
}

_error() {
	echo -e "${RED}ERROR: $@${NC}" >&2
}

_info() {
	echo -e "${WHITE}$@${NC}"
}

_run() {
	local short_name="$1"; shift
	local title="$1"; shift
	local command=$@
	
	# $scene_dir is global
	
	local done_flag="${scene_dir}/.${short_name}_done"
	
	_echo_step "${title}"
	
	if [ -e "$done_flag" ]; then
		_info "  done flag found, skipping step."
		return 0
	fi
	
	if ! $command; then
		_error "step failed, skipping video."
		return 1
	fi
	
	touch "$done_flag"
	
	_info "  done."
	
	return 0
}


### validate requested config

# TODO: check for true/false/auto

if [ "$GAUSSIAN_SPLAT" == "true" ] && [ "$USE_GPU" != "true" ] && [ "$USE_GPU" != "auto" ]; then
	_error "3D Gaussian Splatting construction needs GPU support but USE_GPU is \"${USE_GPU}\", exiting."
	exit 1
fi

if [ -e /dev/nvidia0 ]; then
	has_gpu="true"
else
	has_gpu="false"
fi

if [ "$has_gpu" == "false" ] && [ "$GAUSSIAN_SPLAT" == "true" ]; then
	_error "GAUSSIAN_SPLAT is \"${GAUSSIAN_SPLAT}\" but GPU processing is disabled or no GPU was detected, exiting."
	exit 1
fi

if [ "$USE_GPU" == "true" ]; then
	if [ "$has_gpu" != "true" ]; then
		_error "USE_GPU is \"${USE_GPU}\" but no GPU was detected, exiting."
		exit 1
	fi
	
	use_gpu_int=1
elif [ "$USE_GPU" == "auto" ] && [ "$has_gpu" == "true" ]; then
	use_gpu_int=1
else
	use_gpu_int=0
fi


### add tool dirs to PATH

export PATH="/opt/colmap/bin:${PATH}"

if [ "$GAUSSIAN_SPLAT" == "true" ]; then
	export PATH="/opt/brush:${PATH}"
fi

# COLMAP needs it if it was compiled with CUDA (even when not using it)
if [ -d "/opt/libcudss/lib" ]; then
	export LD_LIBRARY_PATH="/opt/libcudss/lib:${LD_LIBRARY_PATH:-}"
fi


### check if required programs are available

if ! command -v ffmpeg &>/dev/null; then
	_error "FFmpeg not found, exiting."
	exit 1
fi

if ! command -v colmap &>/dev/null; then
	_error "COLMAP not found, exiting."
	exit 1
fi

if [ "$GAUSSIAN_SPLAT" == "true" ]; then
	if ! command -v brush &>/dev/null; then
		_error "Brush not found, exiting."
		exit 1
	fi
fi


### more preparation

step_count=7

if [ "$GAUSSIAN_SPLAT" == "true" ]; then
	step_count=$((step_count + 1))
fi

if [ "$EXTRACT_FPS" == "0" ]; then
	ffmpeg_extra=""
else
	ffmpeg_extra="-vf fps=${EXTRACT_FPS}"
fi
	

### collect videos

shopt -s nullglob
videos=("$VIDEOS_DIR"/*)
video_count=${#videos[@]}

if [ $video_count -eq 0 ]; then
	_info "No video files found in \"${VIDEOS_DIR}\", exiting."
	exit 0
fi


_info "Starting pipeline on ${video_count} videos..."

mkdir -p "$SCENES_DIR"

idx=0
for video in "${videos[@]}"; do
	idx=$((idx + 1))
	
	if [[ ! -f "$video" ]]; then
		_error "$video: does not exist, skipping."
		continue
	fi
	
	video_basename=$(basename "$video")
	video_name="${video_basename%.*}"
	scene_dir="$SCENES_DIR/$video_name"
	img_dir="$scene_dir/images"
	sparse_dir="$scene_dir/sparse"
	splat_dir="$scene_dir/dataset_exports"
	
	
	_echo_title "Video ${idx}/${video_count}: ${video_basename}"
	
	mkdir -p "$img_dir" "$sparse_dir"
	
	_run "ffmpeg_extract_frames" \
		"Step 1/${step_count}: extracting frames using FFmpeg..." \
		ffmpeg -nostdin -loglevel error -stats -i "${video}" $ffmpeg_extra -qscale:v 2 -y "${img_dir}/frame_%06d.jpg" \
		|| continue
	
	_run "colmap_feature_extractor" \
		"Step 2/${step_count}: COLMAP feature extractor..." \
		colmap feature_extractor \
			--database_path "${scene_dir}/database.db" \
			--image_path "${img_dir}" \
			--ImageReader.single_camera 1 \
			--FeatureExtraction.use_gpu $use_gpu_int \
			--FeatureExtraction.num_threads "${SIFT_NUM_THREADS}" \
			--FeatureExtraction.max_image_size "${SIFT_MAX_IMAGE_SIZE}" \
			--SiftExtraction.max_num_features "${SIFT_MAX_NUM_FEATURES}" \
		|| continue
	
	_run "colmap_sequential_matcher" \
		"Step 3/${step_count}: COLMAP sequential matcher..." \
		colmap sequential_matcher \
			--database_path "${scene_dir}/database.db" \
			--FeatureMatching.use_gpu $use_gpu_int \
			--FeatureMatching.num_threads "${SIFT_NUM_THREADS}" \
			--SequentialMatching.overlap "${SEQUENTIAL_OVERLAP}" \
		|| continue
	
	# TODO: colmap view_graph_calibrator
	
	_run "colmap_view_graph_calibrator" \
		"Step 4/${step_count}: COLMAP view graph calibrator..." \
		colmap view_graph_calibrator \
			--database_path "${scene_dir}/database.db" \
		|| continue
	
	_run "colmap_global_mapper" \
		"Step 5/${step_count}: COLMAP global mapper..." \
		colmap global_mapper \
			--database_path "${scene_dir}/database.db" \
			--image_path "${img_dir}" \
			--output_path "${sparse_dir}" \
		|| continue
	
	_run "colmap_model_converter_1" \
		"Step 6/${step_count}: COLMAP model converter to TXT ..." \
		colmap model_converter \
			--input_path  "${sparse_dir}/0" \
			--output_path "${sparse_dir}/0" \
			--output_type TXT \
		|| continue
	
	_run "colmap_model_converter_2" \
		"Step 7/${step_count}: COLMAP model converter to TXT..." \
		colmap model_converter \
			--input_path  "${sparse_dir}/0" \
			--output_path "${sparse_dir}" \
			--output_type TXT \
		|| continue
	
	if [ "$GAUSSIAN_SPLAT" == "true" ]; then
		_run "brush_3dgs" \
			"Step 8/${step_count}: constructing 3D Gaussian Splatting using Brush..." \
			brush "${scene_dir}" \
				--export-path "${splat_dir}" \
				--total-train-iters $BRUSH_TRAIN_ITERS \
			|| continue
	fi
	
	echo ""
	_info "Finished \"${video_name}\""
done

echo ""
_info "All videos finished processing."

exit 0
