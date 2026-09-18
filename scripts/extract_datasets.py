import os
import sys
import subprocess
import glob
import json

ARCHIVES_DIR = "X:/WeddingCullDatasets/archives"
RAW_DIR = "X:/WeddingCullDatasets/raw"
SEVEN_ZIP = r"C:\Program Files\7-Zip\7z.exe"
INVENTORY_FILE = os.path.join(ARCHIVES_DIR, "archive-inventory.json")

def run_7z(archive_path, output_dir, password=None):
    cmd = [SEVEN_ZIP, "x", archive_path, f"-o{output_dir}", "-y"]
    if password:
        cmd.append(f"-p{password}")
    print(f"\n[EXTRACTING] {os.path.basename(archive_path)} -> {output_dir}")
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error extracting {archive_path}: {res.stderr}")
        return False
    print(f"Extraction successful: {os.path.basename(archive_path)}")
    return True

def main():
    os.makedirs(RAW_DIR, exist_ok=True)
    
    # 1. Photo Triage
    pt_archive = os.path.join(ARCHIVES_DIR, "archive.zip")
    pt_raw = os.path.join(RAW_DIR, "PhotoTriage")
    if not os.path.exists(os.path.join(pt_raw, "train_val")):
        run_7z(pt_archive, pt_raw)
    else:
        print("[CACHED] PhotoTriage already extracted.")

    # 2. PARA
    para_pwd = os.environ.get("PARA_ARCHIVE_PASSWORD", "")
    para_archive = os.path.join(ARCHIVES_DIR, "PARA.zip")
    para_raw = os.path.join(RAW_DIR, "PARA")
    if not os.path.exists(os.path.join(para_raw, "PARA", "annotation")):
        if not para_pwd:
            print("ERROR: PARA_ARCHIVE_PASSWORD not set in environment.")
        else:
            run_7z(para_archive, para_raw, password=para_pwd)
    else:
        print("[CACHED] PARA already extracted.")

    # 3. HRIQ
    hriq_raw = os.path.join(RAW_DIR, "HRIQ")
    # 2880x2160 parts 1 & 2
    hriq_2880_out = os.path.join(hriq_raw, "2880x2160")
    os.makedirs(hriq_2880_out, exist_ok=True)
    p1 = os.path.join(ARCHIVES_DIR, "2880x2160-20260918T220232Z-1-001.zip")
    p2 = os.path.join(ARCHIVES_DIR, "2880x2160-20260918T220232Z-1-002.zip")
    if len(glob.glob(f"{hriq_2880_out}/*.jpg")) < 1120:
        run_7z(p1, hriq_raw)
        run_7z(p2, hriq_raw)
    else:
        print("[CACHED] HRIQ 2880x2160 already extracted.")

    # 1024x768
    hriq_1024_out = os.path.join(hriq_raw, "1024x768")
    p1024 = os.path.join(ARCHIVES_DIR, "1024x768-20260918T220231Z-1-001.zip")
    if len(glob.glob(f"{hriq_1024_out}/*.jpg")) < 1120:
        run_7z(p1024, hriq_raw)
    else:
        print("[CACHED] HRIQ 1024x768 already extracted.")

    # 512x384
    hriq_512_out = os.path.join(hriq_raw, "512x384")
    p512 = os.path.join(ARCHIVES_DIR, "512x384-20260918T220230Z-1-001.zip")
    if len(glob.glob(f"{hriq_512_out}/*.jpg")) < 1120:
        run_7z(p512, hriq_raw)
    else:
        print("[CACHED] HRIQ 512x384 already extracted.")

    # 4. CUHK Blur
    cuhk_raw = os.path.join(RAW_DIR, "CUHK_Blur")
    os.makedirs(cuhk_raw, exist_ok=True)
    for b_zip in ["BlurDatasetImage.zip", "BlurDatasetGT.zip", "BlurDatasetResultShi.zip"]:
        run_7z(os.path.join(ARCHIVES_DIR, b_zip), cuhk_raw)

    # 5. CEW
    cew_raw = os.path.join(RAW_DIR, "CEW")
    os.makedirs(cew_raw, exist_ok=True)
    for r_file in ["Dataset_A_Eye_Images.rar", "dataset_B_FacialImages_highResolution.rar", "faceLabels_BioID_CAS-PEAL_AR.rar"]:
        run_7z(os.path.join(ARCHIVES_DIR, r_file), cew_raw)

    # 6. MRL Eye
    mrl_raw = os.path.join(RAW_DIR, "MRLEye")
    os.makedirs(mrl_raw, exist_ok=True)
    mrl_zip = os.path.join(ARCHIVES_DIR, "mrlEyes_2018_01.zip")
    if not os.path.exists(os.path.join(mrl_raw, "mrlEyes_2018_01")):
        run_7z(mrl_zip, mrl_raw)
    else:
        print("[CACHED] MRL Eye already extracted.")

    print("\nAll datasets extracted successfully to", RAW_DIR)

if __name__ == "__main__":
    main()
