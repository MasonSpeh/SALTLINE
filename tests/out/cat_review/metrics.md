# Cat review — §5A numeric gates (raw)

Every row is a measured number from a headless run of the SHIPPED
ship_cat driven through its real behaviour states. `logged` rows are
evidence, not gates.

## walk

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 4.42 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 89 | — | logged |
| hip_y_span_mm | 9.2 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| slide_frame_mm | 7.3338 | < 10.0000 | PASS |
| slide_window_mm | 70.9319 | < 20.0000 | FAIL |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| tail_world_step_max_rad | 0.0077 | < 0.3500 | PASS |
| head_roll_max_deg | 0.1150 | < 3.0000 | PASS |
| head_pitch_span_deg | 2.9341 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.0338 | < 3.5000 | PASS |
| phase_lock | { "n": 20, "mean_phase": 0.06320154659809, "std": 0.00705230274891 } | — | logged |
| pelvis_lock_std_cycles | 0.0071 | < 0.1000 | PASS |

## run

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 7.16 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 5 | — | logged |
| hip_y_span_mm | 29.7 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| slide_frame_mm | 29.7954 | < 10.0000 | FAIL |
| slide_window_mm | 29.7954 | < 20.0000 | FAIL |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| tail_world_step_max_rad | 0.0062 | < 0.3500 | PASS |
| head_roll_max_deg | 0.3412 | < 3.0000 | PASS |
| head_pitch_span_deg | 6.4650 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.1678 | < 3.5000 | PASS |
| phase_lock | { "n": 8, "mean_phase": 0.07664171348966, "std": 0.00960748884568 } | — | logged |
| pelvis_lock_std_cycles | 0.0096 | < 0.1000 | PASS |

## stalk

| metric | value | gate | verdict |
|---|---|---|---|
| stalk_frames | 328 | — | logged |
| hunt_beat_reached | 2 | — | logged |
| prey_is_stub | true | — | logged |
| moved_m | 2.51 | — | logged |
| stance_pairs | 25 | — | logged |
| worst_step_bone | L_Calf | — | logged |
| gait_w_mean_while_moving | 0.9558 | > 0.3000 | PASS |
| slide_frame_mm | 20.1662 | < 10.0000 | FAIL |
| slide_window_mm | 33.4291 | < 20.0000 | FAIL |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |

## carry

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 10.08 | — | logged |
| pose_seen | carry | — | logged |
| stance_pairs | 26 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| slide_frame_mm | 23.2759 | < 10.0000 | FAIL |
| slide_window_mm | 54.5353 | < 20.0000 | FAIL |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| head_roll_max_deg | 2.5154 | < 3.0000 | PASS |

## lookwalk

| metric | value | gate | verdict |
|---|---|---|---|
| head_yaw_mean_deg | -0.02 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| head_roll_max_deg | 0.1157 | < 3.0000 | PASS |
| head_yaw_toward_target_deg | -0.0153 | > 4.0000 | FAIL |
| slide_frame_mm | 7.6162 | < 10.0000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |

## look_cal

| metric | value | gate | verdict |
|---|---|---|---|
| yaw_response_ypr_deg | (33.51, 0.35, 0.04) | — | logged |
| yaw_roll_leak_deg | 0.0390 | < 3.0000 | PASS |
| yaw_gain_deg | 33.5123 | > 14.0000 | PASS |
| pitch_response_ypr_deg | (0.01, 17.27, 0.03) | — | logged |
| pitch_roll_leak_deg | 0.0252 | < 3.0000 | PASS |
| pitch_gain_deg | 17.2708 | > 6.0000 | PASS |

## transitions

| metric | value | gate | verdict |
|---|---|---|---|
| frames | 900 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |

## bigdt

| metric | value | gate | verdict |
|---|---|---|---|
| fixed_joint_step_max | 0.317 | — | logged |
| summed_joint_step_max | 1.086 | — | logged |
| summed_joint_step_max_rad | 1.0860 | < 1.0000 | FAIL |
| yaw_fixed_deg | 100.9 | — | logged |
| yaw_summed_deg | 94.9 | — | logged |
| turn_equivalence_deg | 6.0275 | < 6.0000 | FAIL |
| slope_ease_equivalence_deg | 0.0000 | < 2.5000 | PASS |

## slope_sit

| metric | value | gate | verdict |
|---|---|---|---|
| pose_final | sit | — | logged |
| slope_final_rad | 0.0 | — | logged |
| flat_sit_body_pitch_deg | 0.0000 | < 2.0000 | PASS |

## sanity

| metric | value | gate | verdict |
|---|---|---|---|
| quat_norm_dev_max | 0.0000 | < 0.0010 | PASS |
| bone_len_dev_max_mm | 0.0002 | < 1.5000 | PASS |
| twist_bone_dev_max_rad | 0.0000 | < 0.0200 | PASS |
| nan_frames | 0.0000 | < 0.5000 | PASS |

