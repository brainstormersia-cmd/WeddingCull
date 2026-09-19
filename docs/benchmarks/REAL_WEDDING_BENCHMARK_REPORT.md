# Real Wedding Benchmark Report (Authentic Shoot)

**Execution Provenance:**
- **Platform:** macOS (arm64), Version 14.8.9 (Build 23J631)
- **Git SHA:** `2ac187a6517151e55e36a4ba822f10be23934519`
- **Timestamp:** 2026-09-19T14:16:44Z
- **Throughput:** 9.98 photos/sec (38.47s wall-clock)

## 1. Dataset Classification & Profile

| Metric | Value |
| :--- | :--- |
| **Dataset Name** | wedding_shoot_74ef |
| **Classification** | Category A: Complete Un-culled Wedding Shoot |
| **Camera Model** | NIKON D750 |
| **Time Span** | 2017-09-09T16:54:49Z to 2017-09-09T21:00:36Z (4.1 hours) |
| **Total Photos** | 384 |
| **Sensor Native Resolution** | 6016 x 4016 (24.16 MP) |
| **Camera Counter Continuity** | 384 present / 410 frame span (**93.7% continuity**) |
| **Human Ground Truth** | `NO HUMAN KEEPER GROUND TRUTH AVAILABLE` |

## 2. Autonomously Discovered Workload Reduction

> [!IMPORTANT]
> Bursts were discovered autonomously by `DuplicateAndBurstDetector.detectBursts()` from EXIF capture timestamps and visual similarity, without pre-assigned group IDs.

| Pipeline Metric | Count | % of Shoot |
| :--- | :---: | :---: |
| **Total Input Photos** | 384 | 100.0% |
| **Autonomous Bursts Discovered** | 92 | - |
| **Photos Belonging to Bursts** | 248 | 64.58% |
| **Single Photos (Non-Burst)** | 136 | 35.4% |
| **Collapsed Burst Alternates** | 80 | 20.8% |
| **Review Candidates (Near-Ties)** | 76 | 19.8% |
| **Rejected (Catastrophic Defects / Duplicates)** | 0 | 0.0% |
| **Selected (Curated Album Target)** | 128 | 33.3% |

### Workload Compression Summary

- **Inspection Units Formula:** `Singles (136) + Collapsed Bursts (92) + Review Items (76)`
- **Total Inspection Units:** **304** photos (down from 384)
- **Measured Workload Compression:** **20.83%**

## 3. Burst Audit: Top 10 Largest Bursts

| Burst ID | Frames | Duration | Winner | Winner Score | Runner-Up | Score Diff | Review? |
| :--- | :---: | :---: | :--- | :---: | :--- | :---: | :---: |
| `burst_0c41eca3` | 15 | 3.0s | `_mgo9756_37021035066_o.jpg` | 0.628 | `_mgo9757_37068882641_o.jpg` | 0.000 | YES ⚠️ |
| `burst_e9b8c597` | 7 | 1.0s | `_mgo9819_36374309564_o.jpg` | 0.582 | `_mgo9815_37211242345_o.jpg` | 0.001 | YES ⚠️ |
| `burst_d62a3922` | 5 | 2.0s | `_mgo9586_36813495730_o.jpg` | 0.702 | `_mgo9587_37039309592_o.jpg` | 0.007 | YES ⚠️ |
| `burst_d2259b2b` | 5 | 3.0s | `_mgo9635_37068958461_o.jpg` | 0.695 | `_mgo9637_36374413724_o.jpg` | 0.046 | YES ⚠️ |
| `burst_0ecc0b79` | 5 | 1.0s | `_mgo9799_36374327914_o.jpg` | 0.589 | `_mgo9802_36374324614_o.jpg` | 0.003 | YES ⚠️ |
| `burst_6f873c68` | 4 | 3.0s | `_mgo9603_37068976321_o.jpg` | 0.612 | `_mgo9604_37021116556_o.jpg` | 0.027 | YES ⚠️ |
| `burst_c31631a1` | 4 | 4.0s | `_mgo9681_37068927191_o.jpg` | 0.607 | `_mgo9684_37068770271_o.jpg` | 0.103 | No |
| `burst_a075f057` | 4 | 1.0s | `_mgo9768_36374350564_o.jpg` | 0.608 | `_mgo9767_36374351334_o.jpg` | 0.002 | YES ⚠️ |
| `burst_bf79e6a5` | 4 | 2.0s | `_mgo9773_37039232142_o.jpg` | 0.589 | `_mgo9772_37068872431_o.jpg` | 0.028 | YES ⚠️ |
| `burst_c680bb92` | 4 | 1.0s | `_mgo9775_36374344784_o.jpg` | 0.604 | `_mgo9776_37068870281_o.jpg` | 0.114 | No |

## 4. Burst Audit: 10 Random Bursts

| Burst ID | Frames | Duration | Winner | Winner Score | Runner-Up | Score Diff | Review? |
| :--- | :---: | :---: | :--- | :---: | :--- | :---: | :---: |
| `burst_53257a03` | 2 | 1.0s | `_mgo9573_37039317732_o.jpg` | 0.671 | `_mgo9574_36813501320_o.jpg` | 0.003 | YES ⚠️ |
| `burst_875a0fe6` | 2 | 0.0s | `_mgo9613_37021110016_o.jpg` | 0.73 | `_mgo9614_37021108736_o.jpg` | 0.196 | No |
| `burst_02bb8d2f` | 2 | 1.0s | `_mgo9678_36396839753_o.jpg` | 0.548 | `_mgo9677_36374394194_o.jpg` | 0.011 | YES ⚠️ |
| `burst_752e84f4` | 2 | 0.0s | `_mgo9720_37021059346_o.jpg` | 0.619 | `_mgo9721_37021059056_o.jpg` | 0.131 | No |
| `burst_69a5f0b6` | 3 | 0.0s | `_mgo9763_37068879451_o.jpg` | 0.599 | `_mgo9765_37068878201_o.jpg` | 0.001 | YES ⚠️ |
| `burst_c6dd5e1c` | 2 | 0.0s | `_mgo9796_36374331694_o.jpg` | 0.632 | `_mgo9795_36374333274_o.jpg` | 0.039 | YES ⚠️ |
| `burst_7c4f1159` | 2 | 0.0s | `_mgo9830_36374297974_o.jpg` | 0.622 | `_mgo9831_37211321355_o.jpg` | 0.035 | YES ⚠️ |
| `burst_d5a5dca3` | 2 | 0.0s | `_mgo9853_37068841271_o.jpg` | 0.664 | `_mgo9852_37211310005_o.jpg` | 0.026 | YES ⚠️ |
| `burst_08f50b87` | 2 | 0.0s | `_mgo9879_37211297245_o.jpg` | 0.738 | `_mgo9880_37211296635_o.jpg` | 0.032 | YES ⚠️ |
| `burst_d42f3eb6` | 2 | 0.0s | `_mgo9911_37211275715_o.jpg` | 0.654 | `_mgo9910_37068808381_o.jpg` | 0.002 | YES ⚠️ |

## 5. Burst Audit: Low-Confidence / Near-Tie Review Groups

| Burst ID | Frames | Duration | Winner | Winner Score | Runner-Up | Score Diff | Review Reason |
| :--- | :---: | :---: | :--- | :---: | :--- | :---: | :--- |
| `burst_150b6bd6` | 2 | 0.0s | `_mgo9639_37068955711_o.jpg` | 0.707 | `_mgo9638_37039288682_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_60fcdce9` | 2 | 0.0s | `_mgo9693_36396829433_o.jpg` | 0.656 | `_mgo9692_37068921591_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_10d76fa3` | 2 | 0.0s | `_mgo9727_36374373324_o.jpg` | 0.612 | `_mgo9728_37021053586_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_0c41eca3` | 15 | 3.0s | `_mgo9756_37021035066_o.jpg` | 0.628 | `_mgo9757_37068882641_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_f95025fb` | 3 | 0.0s | `_mgo9823_36374305334_o.jpg` | 0.58 | `_mgo9824_36374304524_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_08b90646` | 2 | 1.0s | `_mgo9847_37211313605_o.jpg` | 0.582 | `_mgo9846_36374289074_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_8c492809` | 2 | 0.0s | `_mgo9902_37211280765_o.jpg` | 0.717 | `_mgo9903_37211280065_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_e9b62337` | 2 | 1.0s | `_mgo9959_36396713663_o.jpg` | 0.616 | `_mgo9958_36813300350_o.jpg` | 0.000 | Ambiguous runner-up (diff <= 0.05) |
| `burst_9df1b4cc` | 2 | 0.0s | `_mgo9609_37021113576_o.jpg` | 0.69 | `_mgo9608_37211245375_o.jpg` | 0.001 | Ambiguous runner-up (diff <= 0.05) |
| `burst_69a5f0b6` | 3 | 0.0s | `_mgo9763_37068879451_o.jpg` | 0.599 | `_mgo9765_37068878201_o.jpg` | 0.001 | Ambiguous runner-up (diff <= 0.05) |

