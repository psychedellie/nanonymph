1. Micromamba Installation
2. Environment Setup from the envs/ directory
3. Database Organization:
  Create separate folders for each database within the $db_root directory. This will ensure each tool can access its respective database. The structure should look like this:
  $db_root/
    ├── amrfinder/
    ├── resfinder/
    ├── plasmidfinder/
    ├── pointfinder/
    └── disinfinder/
4. Absolute Paths for Input and Output: Always use absolute paths for input and output directories. This avoids potential issues related to relative paths in a multi-directory workflow
