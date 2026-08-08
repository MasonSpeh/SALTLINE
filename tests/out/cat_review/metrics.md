# Cat review — §5A numeric gates (raw)

Every row is a measured number from a headless run of the SHIPPED
ship_cat driven through its real behaviour states. `logged` rows are
evidence, not gates.

## walk

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 3.98 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 6 | — | logged |
| hip_y_span_mm | 25.1 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| slide_frame_mm | 6.5109 | < 10.0000 | PASS |
| slide_window_mm | 6.5109 | < 20.0000 | PASS |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| tail_world_step_max_rad | 0.2926 | < 0.3500 | PASS |
| head_roll_max_deg | 0.2438 | < 3.0000 | PASS |
| head_pitch_span_deg | 3.0059 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.0343 | < 3.5000 | PASS |
| phase_lock | { "n": 18, "mean_phase": 0.06123254117162, "std": 0.00502439694988 } | — | logged |
| pelvis_lock_std_cycles | 0.0050 | < 0.1000 | PASS |

## run

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 7.51 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 0 | — | logged |
| hip_y_span_mm | 29.6 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| tail_world_step_max_rad | 0.2803 | < 0.3500 | PASS |
| head_roll_max_deg | 0.3416 | < 3.0000 | PASS |
| head_pitch_span_deg | 6.5780 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.1682 | < 3.5000 | PASS |
| phase_lock | { "n": 8, "mean_phase": 0.07554705013246, "std": 0.01168930778352 } | — | logged |
| pelvis_lock_std_cycles | 0.0117 | < 0.1000 | PASS |

## stalk

| metric | value | gate | verdict |
|---|---|---|---|
| stalk_frames | 386 | — | logged |
| hunt_beat_reached | 2 | — | logged |
| prey_is_stub | true | — | logged |
| moved_m | 2.7 | — | logged |
| stance_pairs | 0 | — | logged |
| worst_step_bone | L_Calf | — | logged |
| gait_w_mean_while_moving | 0.9352 | > 0.3000 | PASS |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |

## carry

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 8.04 | — | logged |
| pose_seen | carry | — | logged |
| stance_pairs | 0 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |
| head_roll_max_deg | 2.6623 | < 3.0000 | PASS |

## lookwalk

| metric | value | gate | verdict |
|---|---|---|---|
| head_yaw_mean_deg | 0.0 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| head_roll_max_deg | 0.2140 | < 3.0000 | PASS |
| head_yaw_toward_target_deg | 0.0002 | > 4.0000 | FAIL |
| slide_frame_mm | 5.9406 | < 10.0000 | PASS |
| joint_step_max_rad | 0.3167 | < 0.3500 | PASS |

## look_cal

| metric | value | gate | verdict |
|---|---|---|---|
| yaw_response_ypr_deg | (33.5, 2.38, 0.04) | — | logged |
| yaw_roll_leak_deg | 0.0355 | < 3.0000 | PASS |
| yaw_gain_deg | 33.5036 | > 14.0000 | PASS |
| pitch_response_ypr_deg | (0.01, 19.07, 0.02) | — | logged |
| pitch_roll_leak_deg | 0.0246 | < 3.0000 | PASS |
| pitch_gain_deg | 19.0664 | > 6.0000 | PASS |

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
| summed_joint_step_max | 1.261 | — | logged |
| summed_joint_step_max_rad | 1.2613 | < 1.0000 | FAIL |
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

