# Cat review — §5A numeric gates (raw)

Every row is a measured number from a headless run of the SHIPPED
ship_cat driven through its real behaviour states. `logged` rows are
evidence, not gates.

## walk

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 5.65 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 100 | — | logged |
| hip_y_span_mm | 6.6 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| slide_frame_mm | 77.4925 | < 10.0000 | FAIL |
| slide_window_mm | 77.4925 | < 20.0000 | FAIL |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.3333 | < 0.3500 | PASS |
| tail_world_step_max_rad | 0.0063 | < 0.3500 | PASS |
| head_roll_max_deg | 0.6420 | < 3.0000 | PASS |
| head_pitch_span_deg | 0.5050 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.0433 | < 3.5000 | PASS |
| phase_lock | { "n": 23, "mean_phase": 0.06555383601752, "std": 0.01089726307603 } | — | logged |
| pelvis_lock_std_cycles | 0.0109 | < 0.1000 | PASS |

## run

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 6.56 | — | logged |
| still_frames | 0 | — | logged |
| stance_pairs | 0 | — | logged |
| hip_y_span_mm | 29.6 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| joint_step_max_rad | 0.8667 | < 0.3500 | FAIL |
| tail_world_step_max_rad | 0.0059 | < 0.3500 | PASS |
| head_roll_max_deg | 0.4031 | < 3.0000 | PASS |
| head_pitch_span_deg | 11.6256 | < 12.0000 | PASS |
| head_yaw_rms_deg | 0.3774 | < 3.5000 | PASS |
| phase_lock | { "n": 11, "mean_phase": 0.45333070443964, "std": 0.01583678143001 } | — | logged |
| pelvis_lock_std_cycles | 0.0158 | < 0.1000 | PASS |

## stalk

| metric | value | gate | verdict |
|---|---|---|---|
| stalk_frames | 386 | — | logged |
| hunt_beat_reached | 2 | — | logged |
| prey_is_stub | true | — | logged |
| moved_m | 2.69 | — | logged |
| stance_pairs | 0 | — | logged |
| worst_step_bone | R_Calf | — | logged |
| gait_w_mean_while_moving | 0.9358 | > 0.3000 | PASS |
| slide_frame_mm | 0.0000 | < 10.0000 | PASS |
| slide_window_mm | 0.0000 | < 20.0000 | PASS |
| joint_step_max_rad | 0.4228 | < 0.3500 | FAIL |

## carry

| metric | value | gate | verdict |
|---|---|---|---|
| moved_m | 11.01 | — | logged |
| pose_seen | carry | — | logged |
| stance_pairs | 15 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| gait_w_mean_while_moving | 1.0000 | > 0.3000 | PASS |
| slide_frame_mm | 17.0568 | < 10.0000 | FAIL |
| slide_window_mm | 17.0568 | < 20.0000 | PASS |
| joint_step_max_rad | 0.6000 | < 0.3500 | FAIL |
| head_roll_max_deg | 0.7084 | < 3.0000 | PASS |

## lookwalk

| metric | value | gate | verdict |
|---|---|---|---|
| head_yaw_mean_deg | 38.81 | — | logged |
| worst_step_bone | R_Forearm | — | logged |
| head_roll_max_deg | 1.4903 | < 3.0000 | PASS |
| head_yaw_toward_target_deg | 38.8060 | > 4.0000 | PASS |
| slide_frame_mm | 58.8058 | < 10.0000 | FAIL |
| joint_step_max_rad | 0.3333 | < 0.3500 | PASS |

## look_cal

| metric | value | gate | verdict |
|---|---|---|---|
| yaw_response_ypr_deg | (33.39, -0.26, -0.22) | — | logged |
| yaw_roll_leak_deg | 0.2236 | < 3.0000 | PASS |
| yaw_gain_deg | 33.3851 | > 14.0000 | PASS |
| pitch_response_ypr_deg | (0.02, 19.64, 0.03) | — | logged |
| pitch_roll_leak_deg | 0.0333 | < 3.0000 | PASS |
| pitch_gain_deg | 19.6378 | > 6.0000 | PASS |

## transitions

| metric | value | gate | verdict |
|---|---|---|---|
| frames | 900 | — | logged |
| worst_step_bone | R_Thigh | — | logged |
| joint_step_max_rad | 0.7009 | < 0.3500 | FAIL |

## bigdt

| metric | value | gate | verdict |
|---|---|---|---|
| fixed_joint_step_max | 0.333 | — | logged |
| summed_joint_step_max | 1.301 | — | logged |
| summed_joint_step_max_rad | 1.3014 | < 1.0000 | FAIL |
| yaw_fixed_deg | 79.1 | — | logged |
| yaw_summed_deg | 85.1 | — | logged |
| turn_equivalence_deg | 6.0275 | < 6.0000 | FAIL |
| slope_ease_equivalence_deg | 0.0000 | < 2.5000 | PASS |

## slope_sit

| metric | value | gate | verdict |
|---|---|---|---|
| pose_final | sit | — | logged |
| slope_final_rad | 0.0 | — | logged |
| flat_sit_body_pitch_deg | 0.0013 | < 2.0000 | PASS |

## sanity

| metric | value | gate | verdict |
|---|---|---|---|
| quat_norm_dev_max | 0.0000 | < 0.0010 | PASS |
| bone_len_dev_max_mm | 0.0002 | < 1.5000 | PASS |
| twist_bone_dev_max_rad | 0.0000 | < 0.0200 | PASS |
| nan_frames | 0.0000 | < 0.5000 | PASS |

