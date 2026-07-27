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

shared_inputs:
  - id: input_dir
    type: Directory
    doc: Input directory containing DICOM data for one case or series.
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
