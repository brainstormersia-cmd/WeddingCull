#!/usr/bin/env python3
import os
import re
from datetime import datetime
from PIL import Image, ExifTags

def audit_74ef():
    folder = "datasets/wedding/extracted/wedding_shoot_74ef"
    files = sorted(os.listdir(folder))
    print(f"\n==========================================")
    print(f"DEEP AUDIT: wedding_shoot_74ef ({len(files)} files)")
    print(f"==========================================")
    
    frame_nums = []
    exif_records = []
    for f in files:
        m = re.search(r'_mgo(\d+)', f.lower())
        num = int(m.group(1)) if m else None
        frame_nums.append(num)
        
        p = os.path.join(folder, f)
        dt = None
        try:
            with Image.open(p) as im:
                raw_exif = im._getexif()
                if raw_exif:
                    exif = {ExifTags.TAGS.get(k, k): v for k, v in raw_exif.items()}
                    dt_str = exif.get("DateTimeOriginal")
                    if dt_str:
                        dt = datetime.strptime(str(dt_str), "%Y:%m:%d %H:%M:%S")
        except Exception:
            pass
        exif_records.append((f, num, dt))
    
    valid_nums = [n for n in frame_nums if n is not None]
    min_num, max_num = min(valid_nums), max(valid_nums)
    span = max_num - min_num + 1
    print(f"Frame number range: _MGO{min_num:04d} to _MGO{max_num:04d}")
    print(f"Total frame span in camera counter: {span}")
    print(f"Number of frames present: {len(valid_nums)}")
    print(f"Frame presence ratio: {len(valid_nums) / span * 100:.1f}%")
    
    # Check consecutive frame blocks
    sorted_nums = sorted(valid_nums)
    gaps = []
    consecutive_bursts = []
    current_burst = [sorted_nums[0]]
    for i in range(1, len(sorted_nums)):
        diff = sorted_nums[i] - sorted_nums[i-1]
        if diff == 1:
            current_burst.append(sorted_nums[i])
        else:
            if len(current_burst) > 1:
                consecutive_bursts.append(current_burst)
            current_burst = [sorted_nums[i]]
            gaps.append(diff - 1)
    if len(current_burst) > 1:
        consecutive_bursts.append(current_burst)

    print(f"Consecutive frame bursts (diff == 1): {len(consecutive_bursts)}")
    burst_lens = [len(b) for b in consecutive_bursts]
    print(f"Burst lengths: min={min(burst_lens) if burst_lens else 0}, max={max(burst_lens) if burst_lens else 0}, mean={sum(burst_lens)/len(burst_lens) if burst_lens else 0:.1f}")
    print(f"Total photos in consecutive frame bursts: {sum(burst_lens)} ({sum(burst_lens)/len(valid_nums)*100:.1f}%)")
    print(f"Top 5 largest consecutive bursts: {sorted(burst_lens, reverse=True)[:5]}")
    print(f"Total frame gaps: {len(gaps)}, total missing frames: {sum(gaps)}")

    # Time-based bursts (within 2 seconds)
    sorted_by_time = sorted([r for r in exif_records if r[2] is not None], key=lambda x: x[2])
    time_bursts = []
    curr_t_burst = [sorted_by_time[0]]
    for i in range(1, len(sorted_by_time)):
        delta = (sorted_by_time[i][2] - sorted_by_time[i-1][2]).total_seconds()
        if delta <= 2.0:
            curr_t_burst.append(sorted_by_time[i])
        else:
            if len(curr_t_burst) > 1:
                time_bursts.append(curr_t_burst)
            curr_t_burst = [sorted_by_time[i]]
    if len(curr_t_burst) > 1:
        time_bursts.append(curr_t_burst)

    print(f"\nTime-based bursts (<= 2.0s apart): {len(time_bursts)}")
    t_burst_lens = [len(b) for b in time_bursts]
    print(f"Time burst lengths: min={min(t_burst_lens) if t_burst_lens else 0}, max={max(t_burst_lens) if t_burst_lens else 0}, mean={sum(t_burst_lens)/len(t_burst_lens) if t_burst_lens else 0:.1f}")
    print(f"Total photos in time bursts: {sum(t_burst_lens)} ({sum(t_burst_lens)/len(sorted_by_time)*100:.1f}%)")
    print(f"Top 5 largest time bursts: {sorted(t_burst_lens, reverse=True)[:5]}")

def audit_other(folder_name):
    folder = os.path.join("datasets/wedding/extracted", folder_name)
    files = sorted(os.listdir(folder))
    print(f"\n==========================================")
    print(f"DEEP AUDIT: {folder_name} ({len(files)} files)")
    print(f"==========================================")
    
    frame_nums = []
    for f in files:
        m = re.search(r'(?:crw|img)_(\d+)', f.lower())
        if m:
            frame_nums.append(int(m.group(1)))
    if frame_nums:
        min_n, max_n = min(frame_nums), max(frame_nums)
        span = max_n - min_n + 1
        print(f"Frame number range: {min_n} to {max_n}, span: {span}")
        print(f"Frames present: {len(frame_nums)} / {span} ({len(frame_nums)/span*100:.1f}%)")
    else:
        print("No standard camera frame numbers found.")

if __name__ == "__main__":
    audit_74ef()
    audit_other("wedding_shoot_84ec")
    audit_other("wedding_shoot_fac0")
