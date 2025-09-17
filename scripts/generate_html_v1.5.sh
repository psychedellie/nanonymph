#!/bin/bash

# Folder containing the tab-delimited text files
export PATH=$PATH:$(pwd)
folder_path=$(pwd)

# Generate the timestamp for the HTML filename
timestamp=$(date +"%Y-%m-%d_%H:%M")
output_file="results_$timestamp.html"

# List of columns to be excluded
excluded_columns=("Protein identifier" "Strand" "Sequence name" "Scope" "Target length" "Reference sequence length" "HMM id" "HMM description")

# Create the initial HTML structure with a dark theme and bioinformatics styling
cat <<EOF > $output_file
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="description" content="AMR Finder + | Results">
    <meta name="keywords" content="AMR Finder, Results, Data Table, Responsive, Bioinformatics">
    <title>AMR Finder + | Results</title>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script> <!-- Include SheetJS for Excel file generation -->
    <style>
        body {
            background-color: #1b1f24;
            color: #e0e0e0;
            font-family: 'Courier New', Courier, monospace;
            margin: 20px;
        }
        h1 {
            text-align: center;
            font-size: 2em;
            color: #8ab4f8;
            border-bottom: 2px solid #8ab4f8;
            padding-bottom: 10px;
            margin-bottom: 30px;
        }
        #controls {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }
        #left-controls {
            display: flex;
            align-items: center;
        }
        #left-controls select, #left-controls button {
            padding: 10px;
            margin-right: 10px;
            background-color: #3a3f44;
            color: #e0e0e0;
            border: 1px solid #8ab4f8;
            border-radius: 5px;
            cursor: pointer;
        }
        #left-controls select {
            background-color: #3a3f44;
        }
        #left-controls button {
            background-color: #8ab4f8;
            color: #1b1f24;
            border: none;
            border-radius: 5px;
        }
        #left-controls button:hover {
            background-color: #709ace;
        }
        #right-controls {
            display: flex;
            align-items: center;
        }
        #right-controls select {
            padding: 10px;
            margin-left: 10px;
            background-color: #3a3f44;
            color: #e0e0e0;
            border: 1px solid #8ab4f8;
            border-radius: 5px;
            cursor: pointer;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
            box-shadow: 0 0 15px rgba(138, 180, 248, 0.5);
        }
        th, td {
            border: 1px solid #3a3f44;
            padding: 10px;
            text-align: left;
            word-wrap: break-word;
        }
        th {
            background-color: #30363d;
            color: #8ab4f8;
            font-size: 1em;
        }
        tr:nth-child(even) {
            background-color: #24292f;
        }
        tr:nth-child(odd) {
            background-color: #1f2328;
        }
        tr:hover {
            background-color: #3a3f44;
        }
        #table_results {
            border: 1px solid #8ab4f8;
        }
        @media screen and (max-width: 600px) {
            table, thead, tbody, th, td, tr {
                display: block;
            }
            th, td {
                width: 100%;
                box-sizing: border-box;
            }
            tr {
                margin-bottom: 10px;
            }
        }
    </style>
    <script>
        let methodColumnIndex = -1; // Global variable to hold the index of the "Method" column

        // Function to set the index of the "Method" column based on the final header structure
        function setMethodColumnIndex() {
            const table = document.getElementById("table_results");
            const headerCells = table.getElementsByTagName("th");
            for (let i = 0; i < headerCells.length; i++) {
                if (headerCells[i].innerText === "Method") {
                    methodColumnIndex = i; // Set the correct index for the "Method" column
                    break;
                }
            }
        }

        // Function to filter the table based on the selected sample and method
        function filterTable() {
            if (methodColumnIndex === -1) setMethodColumnIndex(); // Ensure methodColumnIndex is set before filtering

            var sampleDropdown = document.getElementById("select_sample");
            var selectedSample = sampleDropdown.value;
            var methodDropdown = document.getElementById("select_method");
            var selectedMethod = methodDropdown.value.toLowerCase(); // Convert to lowercase for case-insensitive match

            var table = document.getElementById("table_results");
            var rows = table.getElementsByTagName("tr");

            for (var i = 1; i < rows.length; i++) { // Skip header row
                var sampleColumn = rows[i].getElementsByTagName("td")[0];
                var methodColumn = rows[i].getElementsByTagName("td")[methodColumnIndex]; // Use dynamically determined "Method" column index

                var sampleMatch = (selectedSample === "All samples" || sampleColumn.innerHTML === selectedSample);
                var methodMatch = (selectedMethod === "select method" || methodColumn.innerHTML.toLowerCase().indexOf(selectedMethod) !== -1);

                rows[i].style.display = (sampleMatch && methodMatch) ? "" : "none";
            }
        }

        // Function to get the current filtering values for the file name
        function getFilteredFileName() {
            var sampleDropdown = document.getElementById("select_sample");
            var selectedSample = sampleDropdown.value.toLowerCase().replace(/\s+/g, "_"); // Replace spaces with underscores

            var methodDropdown = document.getElementById("select_method");
            var selectedMethod = methodDropdown.value.toLowerCase().replace(/\s+/g, "_"); // Replace spaces with underscores

            var filename = "filtered_table-" + selectedSample + "-" + selectedMethod;
            return filename;
        }

        // Function to download the filtered table in the selected format
        function downloadTable() {
            var formatDropdown = document.getElementById("select_format");
            var format = formatDropdown.value; // Get selected file format
            var table = document.getElementById("table_results");
            var rows = table.getElementsByTagName("tr");

            var content = [];
            var headers = Array.from(rows[0].getElementsByTagName("th")).map(function(th) {
                return th.innerText;
            });
            content.push(headers);

            for (var i = 1; i < rows.length; i++) { // Skip header row
                if (rows[i].style.display !== "none") { // Include only visible rows
                    var row = Array.from(rows[i].getElementsByTagName("td")).map(function(td) {
                        return td.innerText;
                    });
                    content.push(row);
                }
            }

            var filename = getFilteredFileName();

            if (format === "CSV") {
                var csvString = content.map(row => row.join(",")).join("\\n");
                var blob = new Blob([csvString], { type: "text/csv;charset=utf-8;" });
                var downloadLink = document.createElement("a");
                downloadLink.href = URL.createObjectURL(blob);
                downloadLink.download = filename + ".csv";
                downloadLink.style.display = "none";
                document.body.appendChild(downloadLink);
                downloadLink.click();
                document.body.removeChild(downloadLink);
            } else if (format === "Excel") {
                // Use SheetJS to create an XLSX file
                var wb = XLSX.utils.book_new();
                var ws = XLSX.utils.aoa_to_sheet(content); // Convert array of arrays to worksheet
                XLSX.utils.book_append_sheet(wb, ws, "Results");
                XLSX.writeFile(wb, filename + ".xlsx");
            } else if (format === "TSV") {
                var tsvString = content.map(row => row.join("\\t")).join("\\n");
                var blob = new Blob([tsvString], { type: "text/tab-separated-values;charset=utf-8;" });
                var downloadLink = document.createElement("a");
                downloadLink.href = URL.createObjectURL(blob);
                downloadLink.download = filename + ".tsv";
                downloadLink.style.display = "none";
                document.body.appendChild(downloadLink);
                downloadLink.click();
                document.body.removeChild(downloadLink);
            }
        }

        // Call setMethodColumnIndex after the table is fully loaded
        window.onload = function() {
            setMethodColumnIndex();
        };
    </script>
</head>
<body>
    <h1>AMR Finder + | Results</h1>
    <div id="controls">
        <!-- Left Controls: Format Dropdown and Download Button -->
        <div id="left-controls">
            <select id="select_format">
                <option value="CSV">CSV</option>
                <option value="Excel">Excel</option>
                <option value="TSV">TSV</option>
            </select>
            <button onclick="downloadTable()">Download</button>
        </div>

        <!-- Right Controls: Sample and Method Dropdowns -->
        <div id="right-controls">
            <select id="select_sample" onchange="filterTable()">
                <option value="All samples">All samples</option>
EOF

# Read the text files and generate the dropdown options and table rows
for file in "$folder_path"/*.txt; do
    # Extract the filename without extension
    filename=$(basename "$file" .txt)
    
    # Append the sample name to the dropdown list
    echo "                <option value=\"$filename\">$filename</option>" >> $output_file
done

# Close the sample dropdown select element
echo "            </select>" >> $output_file

# Add the methods dropdown with predefined values
cat <<EOF >> $output_file
            <select id="select_method" onchange="filterTable()">
                <option value="select method">select method</option>
                <option value="Allele">Allele</option>
                <option value="Blast">Blast</option>
                <option value="Exact">Exact</option>
                <option value="Partial">Partial</option>
                <option value="Point">Point</option>
            </select>
        </div>
    </div>

    <table id="table_results">
        <thead>
EOF

# Use the first file to create the table header and identify excluded columns by index
first_file=$(ls "$folder_path"/*.txt | head -n 1)
declare -a exclude_indices=() # Array to store indices of columns to be excluded
if [ -f "$first_file" ]; then
    # Read the header line and get the columns
    header=$(head -n 1 "$first_file")
    IFS=$'\t' read -r -a columns <<< "$header"

    # Generate the header row excluding specified columns and store indices to exclude
    echo "            <tr><th>Sample</th>" >> $output_file
    for i in "${!columns[@]}"; do
        if [[ ! " ${excluded_columns[@]} " =~ " ${columns[$i]} " ]]; then
            echo "<th>${columns[$i]}</th>" >> $output_file
        else
            exclude_indices+=("$i") # Store index of excluded column
        fi
    done
    echo "</tr>" >> $output_file
fi

echo "        </thead>" >> $output_file
echo "        <tbody>" >> $output_file

# Populate the table with data from each file, excluding specified columns
for file in "$folder_path"/*.txt; do
    filename=$(basename "$file" .txt)
    # Skip the header line and add data rows
    tail -n +2 "$file" | while IFS=$'\t' read -r -a columns; do
        row="<tr><td>$filename</td>"
        for i in "${!columns[@]}"; do
            # Include only columns that are not in exclude_indices
            if [[ ! " ${exclude_indices[@]} " =~ " $i " ]]; then
                row="$row<td>${columns[$i]}</td>"
            fi
        done
        row="$row</tr>"
        echo "            $row" >> $output_file
    done
done

# Close the table and HTML tags
echo "        </tbody>" >> $output_file
echo "    </table>" >> $output_file
echo "</body>" >> $output_file
echo "</html>" >> $output_file

echo "HTML file '$output_file' has been generated successfully."
