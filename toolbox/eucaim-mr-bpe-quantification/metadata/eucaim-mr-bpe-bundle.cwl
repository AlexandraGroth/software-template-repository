# EUCAIM FEM bundle definition
cwlVersion: v1.2
class: FEMBundle

id: eucaim-mr-bpe-quantification-bundle
label: EUCAIM MR BPE Quantification Bundle
doc: Executes one BPE quantification task at one EUCAIM compute site.

mode: standalone

tasks:
  - task_id: eucaim-mr-bpe-quantification
    role: worker
    multiplicity:
      type: single
      doc: One task instance processes one input case or series.

# NOTE: shared_inputs/shared_outputs aren't required for single-task bundles
# (WP6 guidance, 2026-08) but are kept here for explicit bundle-level contract.
shared_inputs:
  - id: input_dir
    type: Directory
    doc: >
      Either a single DICOM case/series folder, or a full EUCAIM CDM
      Structure directory (imaging_mandatory_view.csv plus
      dataset/imaging_data/<patient_id>/<study_uid>/<series_uid>/...) for
      batch processing of multiple cases. See README_HRC.md for details.
    required: true
    default: null
    hidden: false
    constraints: {}
    targets:
      - task_id: eucaim-mr-bpe-quantification
        task_input_name: input_dir

shared_outputs:
  - id: results_csv
    type: File
    doc: Main BPE quantification result table.
    source:
      task_id: eucaim-mr-bpe-quantification
      task_output_name: results_csv

dependencies: []

metadata:
  author: Philips
  version: "1.0.0"
  orchestrator:
    additional_metadata: {}
