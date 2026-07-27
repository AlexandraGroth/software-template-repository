# EUCAIM FEM workflow definition
cwlVersion: v1.2
class: FEMWorkflow

id: eucaim-mr-bpe-quantification-workflow
label: EUCAIM MR BPE Quantification Workflow
doc: Runs BPE quantification for one DCE breast MR case or series.

execution_sites:
  - alias: processing_site
    kind: single
    selection: user
    value: null
    doc: EUCAIM data node at which the BPE task is executed.

bundles:
  - bundle_id: eucaim-mr-bpe-quantification-bundle
    doc: Executes the BPE quantification container.
    site_bindings:
      - role: worker
        site: processing_site

inputs:
  - id: input_dir
    type: Directory
    doc: Input directory containing DICOM data for one case or series.
    required: true
    default: null
    hidden: false
    scope: per_node
    constraints: {}
    targets:
      - bundle_id: eucaim-mr-bpe-quantification-bundle
        bundle_input_name: input_dir

outputs:
  - id: results_csv
    type: File
    doc: Main BPE quantification result table.
    source:
      bundle_id: eucaim-mr-bpe-quantification-bundle
      bundle_output_name: results_csv

connections: []

metadata:
  author: Philips
  version: "1.0.0"
  apps: {}
  version_control:
    repository: ""
    branch: ""
    commit: ""
    tag: "1.0.0"
