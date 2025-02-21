# Place a cross on disable symbols.
# Remember to click "Don't show again" window after update the symbol.

# 1. Open DSN file and generate BOM to get the disable part reference.
# 2. Export EDF file to get page, symbol coordinates & size and folder name.
# 3. Based on the information, place a cross on those symbols.

set localWorkDir "local"
set capAutoLoad "C:/Cadence/SPB_23.1/tools/capture/tclscripts/capAutoLoad/"

proc main {inputDSNFilePath} {
	set inputDSNFilePath [string map {\\ /} $inputDSNFilePath]
	InitSetup $inputDSNFilePath
	exec cmd /c "cd /d C:/Cadence/SPB_23.1/tools/bin && capture //PlaceCrossCMD.tcl"
	DeleteFiles
	puts "All processes done. You can find updated DSN at your input path."
	exit
}

proc InitSetup {inputDSNFilePath} {
	# Create work directory, process xml files.
	puts "Setting Environment..."
	global localWorkDir
	
	CreateFolder $localWorkDir
	CopyFiles2Local
	
	set dsnName [file tail $inputDSNFilePath]
	set dsnPureName [file rootname $dsnName]
	set dsnDirName [file dirname $inputDSNFilePath]
	
	CreateFolder "${dsnDirName}/${dsnPureName}_cross"
	
	ReplaceTXTKeyword "${localWorkDir}Bill_of_Materials.xml" "input_file_pure_name" $dsnPureName
	ReplaceTXTKeyword "${localWorkDir}Select_Project_Type.xml" "input_file_pure_name" $dsnPureName
	after 1000
	ReplaceTXTKeyword "${localWorkDir}Select_Project_Type.xml" "input_file_dir_path" $dsnDirName
	ReplaceTXTKeyword "${localWorkDir}PlaceCrossCMD.tcl" "input_DSN_file_path" $inputDSNFilePath
}

proc CreateFolder {folderPath} {
	# Create a folder path.
	set isdir [file isdirectory $folderPath]
	if {$isdir eq 0} {
		file mkdir $folderPath
	}
}

proc CopyFiles2Local {} {
	global localWorkDir
	global capAutoLoad
	
	# Copy xml files from file server to C:/BIOS/OrCADSch/PlaceCross.
	set fileSvrPath "//serverPath"
	file copy -force "${fileSvrPath}XML/Select_Project_Type.xml" $localWorkDir
	file copy -force "${fileSvrPath}XML/Bill_of_Materials.xml" $localWorkDir
	file copy -force "${fileSvrPath}XML/Save_Part_Instance.xml" $localWorkDir
	
	# Copy tcl code to capAutoLoad
	file copy -force "${fileSvrPath}TclCode/GlobalProc.tcl" $capAutoLoad
	file copy -force "${fileSvrPath}TclCode/ReadFiles.tcl" $capAutoLoad
	file copy -force "${fileSvrPath}TclCode/PlaceCross.tcl" $capAutoLoad
	
	file copy -force "${fileSvrPath}TclCode/PlaceCrossCMD.tcl" $localWorkDir
}

proc ReplaceTXTKeyword {TXTFilePath oldText newText} {
	# Check if the file exists.
    if {![file exists $TXTFilePath]} {
        puts "Error: File $TXTFilePath does not exist."
        return
    }

    # Read the file content.
	set readFileHandle [open $TXTFilePath r]
    set fileContent [read $readFileHandle]
	close $readFileHandle

    # Replace the old text with the new text.
    set updatedContent [string map [list $oldText $newText] $fileContent]

    # Write the updated content back to the file.
    set writeFileHandle [open $TXTFilePath w]
    puts -nonewline $writeFileHandle $updatedContent
	close $writeFileHandle
}

proc DeleteFiles {} {
	# Delete all related files.
	global localWorkDir
	global capAutoLoad
	
	file delete -force "${capAutoLoad}GlobalProc.tcl"
	file delete -force "${capAutoLoad}PlaceCross.tcl"
	file delete -force "${capAutoLoad}ReadFiles.tcl"
	# Remove entire folder.
	foreach $localWorkDir [glob *] {
		file delete -force -- $localWorkDir
	}
}

if {$argc == 0} {
	puts "Usage: mytcl.exe param"
    exit
} else {
	set inputFilePath [lindex $argv 0]
	set fileExtension [file extension $inputFilePath]
	if {$fileExtension eq ".DSN"} {
		puts "=====Start placing \'X\' on symbols====="
		main $inputFilePath
	} else {
		puts "Please input DSN file."
		exit
	}
}
