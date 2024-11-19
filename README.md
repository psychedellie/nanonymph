## Flye-Only Branch

This branch of the workflow is streamlined to use **Flye** as the sole assembler for processing Nanopore sequencing data. While the assembly step is simplified, all subsequent steps, including polishing, annotation, and analyses, remain consistent with the main workflow.

### Key Features:

- **Assembly:** Utilizes Flye for assembling raw reads.
- **Polishing:** Uses Medaka to polish the Flye assemblies.
- **Annotation:** Employs Prokka for annotating the polished assemblies.
- **Typing and Analysis:** Includes rMLST, MLST, PlasmidFinder, AMRFinderPlus, and ResFinder for comprehensive sequence analysis.

This branch is ideal for users who prefer or require Flye for their assembly needs while maintaining the robustness of the full workflow.
