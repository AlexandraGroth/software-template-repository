# EUCAIM FEM task definition
cwlVersion: v1.2
class: FEMTask

id: eucaim-mr-bpe-quantification
label: EUCAIM MR BPE Quantification
doc: >
  Quantifies background parenchymal enhancement from DCE breast MR DICOM
  data for one case or series.

requirements:
  - class: DockerRequirement
    dockerPull: harbor.eucaim.cancerimage.eu/processing-tools/eucaim-mr-bpe-quantification:1.0.0

# The image defines the same entrypoint explicitly here so the command is not
# hidden inside the image (see README_HRC.md "How to run" section):
#   ENTRYPOINT ["/miniforge3/envs/omnilearn/bin/python", "-m", "bpe_app.app"]
baseCommand:
  - /miniforge3/envs/omnilearn/bin/python
  - -m
  - bpe_app.app

inputs:
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
    source: user
    constraints: {}
    inputBinding:
      position: 1
      prefix: --input
      separate: true

  - id: output_dir
    type: string
    doc: FEM-managed writable runtime output directory.
    required: true
    default: /output
    hidden: true
    source: user
    constraints: {}
    inputBinding:
      position: 2
      prefix: --output
      separate: true
      valueFrom: $(runtime.outdir)

  - id: no_register
    type: boolean
    doc: Disable image registration for the EUCAIM runtime workflow.
    required: true
    default: true
    hidden: true
    source: user
    constraints: {}
    inputBinding:
      position: 3
      prefix: --noregister
      separate: false

outputs:
  - id: results_csv
    type: File
    doc: Main BPE quantification result table.
    outputBinding:
      glob: results.csv

expectedExitCode: 0

metadata:
  author: Philips
  version: "1.0.0"
  orchestrator:
    network: bridge
    additional_metadata: {}
