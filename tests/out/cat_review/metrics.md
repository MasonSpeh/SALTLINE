# Cat review — §5A numeric gates (raw)

Every row is a measured number from a headless run of the SHIPPED
ship_cat driven through its real behaviour states. `logged` rows are
evidence, not gates.

## walk

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 5.61 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 20 | — | logged |
| hip_y_span_mm | 11.9 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| slide_frame_mm | 15.2571 | < 10.0000 | FAIL |
| slide_window_mm | 18.2446 | < 20.0000 | PASS |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.6785 | < 0.3500 | FAIL |
| tail_world_step_max_rad | 0.2796 | < 0.3500 | PASS |
| head_roll_max_deg | 0.1482 | < 3.0000 | PASS |
| head_pitch_span_deg | 2.9331 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.0337 | < 3.5000 | PASS |
| phase_lock | { "n": 21, "mean_phase": 0.06218811935001, "std": 0.01086445617411 } | — | logged |
| pelvis_lock_std_cycles | 0.0109 | < 0.1000 | PASS |

## run

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 7.5 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 0 | — | logged |
| hip_y_span_mm | 29.7 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.9624 | < 0.3500 | FAIL |
| tail_world_step_max_rad | 0.2796 | < 0.3500 | PASS |
| head_roll_max_deg | 0.3416 | < 3.0000 | PASS |
| head_pitch_span_deg | 6.6078 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.1680 | < 3.5000 | PASS |
| phase_lock | { "n": 9, "mean_phase": 0.07871349347825, "std": 0.01296531731668 } | — | logged |
| pelvis_lock_std_cycles | 0.0130 | < 0.1000 | PASS |

## stalk

| metric | value | gate | verdict |
|---|---|---|---|
| stalk_frames | 386 | — | logged |
| hunt_beat_reached | 2 | — | logged |
| prey_is_stub | true | — | logged |
| moved_m | 2.7 | — | logged |
| stance_pairs | 25 | — | logged |
| worst_step_bone | R_Calf | — | logged |
| gait_w_mean_while_moving | 0.9352 | > 0.3000 | PASS |
| slide_frame_mm | 10.4003 | < 10.0000 | FAIL |
| slide_window_mm | 20.7654 | < 20.0000 | FAIL |
| joint_step_max_rad | 1.4700 | < 0.3500 | FAIL |

## carry

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 11.01 | — | logged |
| pose_seen | carry | — | logged |
| stance_pairs | 0 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| joint_step_max_rad | 0.7855 | < 0.3500 | FAIL |
| head_roll_max_deg | 1.4770 | < 3.0000 | PASS |

## lookwalk

| metric | value | gate | verdict |
|---|---|---|---|
| head_yaw_mean_deg | 0.0 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| head_roll_max_deg | 0.1447 | < 3.0000 | PASS |
| head_yaw_toward_target_deg | 0.0000 | > 4.0000 | FAIL |
| slide_frame_mm | 16.5638 | < 10.0000 | FAIL |
| joint_step_max_rad | 0.6510 | < 0.3500 | FAIL |

## look_cal

| metric | value | gate | verdict |
|---|---|---|---|
| yaw_response_ypr_deg | (33.5, 2.4, 0.02) | — | logged |
| yaw_roll_leak_deg | 0.0237 | < 3.0000 | PASS |
| yaw_gain_deg | 33.5032 | > 14.0000 | PASS |
| pitch_response_ypr_deg | (0.01, 18.95, 0.02) | — | logged |
| pitch_roll_leak_deg | 0.0227 | < 3.0000 | PASS |
| pitch_gain_deg | 18.9546 | > 6.0000 | PASS |

## transitions

| metric | value | gate | verdict |
|---|---|---|---|
| frames | 900 | — | logged |
| worst_step_bone | L_Forearm | — | logged |
| joint_step_max_rad | 0.6741 | < 0.3500 | FAIL |

## bigdt

| metric | value | gate | verdict |
|---|---|---|---|
| fixed_joint_step_max | 0.607 | — | logged |
| summed_joint_step_max | 1.086 | — | logged |
| summed_joint_step_max_rad | 1.0860 | < 1.0000 | FAIL |
| yaw_fixed_deg | 79.1 | — | logged |
| yaw_summed_deg | 85.1 | — | logged |
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

