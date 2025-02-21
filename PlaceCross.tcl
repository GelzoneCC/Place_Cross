#========== Subroutine ==========
proc PlaceCross {inputDSNFilePath} {
	# Place cross on disable symbols.
	puts "Opening DSN file..."
	
	set dsnName [file tail $inputDSNFilePath]
	set dsnPureName [file rootname $dsnName]
	set dsnDirName [file dirname $inputDSNFilePath]
	
	MenuCommand "57601" | FileDialog  "OK" $inputDSNFilePath 2 | DialogBox  "OK" "//Select_Project_Type.xml"
	puts "Done"
	after 2000
	
	# Export EDF file.
	puts "Creating EDF file..."
	XMATIC_CAP2EDIF $inputDSNFilePath "//${dsnPureName}.EDF" "C:/Cadence/SPB_23.1/tools/capture/CAP2EDI.CFG"
	puts "Done"
	after 3000
	
	# Export BOM.
	puts "Generating BOM..."
	Menu "Tools::Bill of Materials" | DialogBox  "OK" "//Bill_of_Materials.xml"
	set bomFileName "//${dsnPureName}.BOM"
	ReadFiles create readBOM $bomFileName "BOM"
	set bomList [readBOM readFile "\t"]
	set bomListLen [llength $bomList]
	after 1000
	
	# Get the reference name for the disables. (Check BOM Structure to get Reference)
	puts "Collecting disable reference name..."
	set disableRefDict {}
	for {set i 14} {$i < $bomListLen} {incr i} {
		set rowData [lindex $bomList $i]
		set ref [lindex $rowData 0]
		set partNumber [lindex $rowData 1]
		set bomStruct [lindex $rowData 3]
		
		if {[string length $partNumber] == 11 || [string first "SHRT" $ref] == 0} {
			# "SHRT" part reference has no part number but with NI.
			if {$bomStruct eq "@"} {
				# Use dict {part reference: part number} to identify IC symbol.
				dict set disableRefDict $ref $partNumber
			}
		}
	}
	
	# Processing EDF file.
	set filterEDFList [EDFCleaning "//${dsnPureName}.EDF"]
	set schFolderName [GetSchematicFolderName $filterEDFList]
	
	# Add another dict to store ref dict as value and page as key.
	set refWithPage {}
	dict for {keyVar valueVar} $disableRefDict {
		set partRef $keyVar
		set partNumber $valueVar
		set schPage [GetSchematicPage $filterEDFList $partRef]
		set symbolCoor [GetSymbolCoordinates $filterEDFList $partRef]
		set coorX [lindex $symbolCoor 0]
		set coorY [lindex $symbolCoor 1]
		# SA for IC, SD & SE fixed.
		if {[string first "SE" $partNumber] == 0} {
			# Capacitance -> 2x1
			set symbolWidth 0.2
			set symbolHeight 0.1
		} elseif {[string first "SD" $partNumber] == 0} {
			# Resistance -> 2x3
			set symbolWidth 0.2
			set symbolHeight 0.3
		} elseif {[string first "SA" $partNumber] == 0} {
			# IC
			set symbolSize [GetSymbolSize $filterEDFList $partRef]
			set symbolWidth [lindex $symbolSize 0]
			set symbolHeight [lindex $symbolSize 1]
		} else {
			# Others
			set symbolWidth 0.2
			set symbolHeight 0.1
		}
		
		# Add attributes to a part reference.
		set refDict {}
		dict lappend refDict $partRef $coorX
		dict lappend refDict $partRef $coorY
		dict lappend refDict $partRef $symbolWidth
		dict lappend refDict $partRef $symbolHeight
		
		dict lappend refWithPage $schPage $refDict
	}

	set uncrossedPart {}
	dict for {keyVar valueVar} $refWithPage {
		set schPage $keyVar
		set partRefInfo $valueVar
		puts $partRefInfo
		set partRefPerPage [llength $partRefInfo]
		
		# Click the target page.
		SelectPMItem $schFolderName
		SelectPMItem $schPage
		OPage $schFolderName $schPage
		after 2000
		#capDisplayMessageBox "Break point.\nPress to continue." "Interrupt."
		# "valueVar" store part ref. information as a list.
		for {set eachPart 0} {$eachPart < $partRefPerPage} {incr eachPart} {
			set part [lindex $partRefInfo $eachPart]
			set partRef [lindex $part 0]
			set attrs [lindex $part 1]
			set coorX [lindex $attrs 0]
			set coorY [lindex $attrs 1]
			set symbolWidth [lindex $attrs 2]
			set symbolHeight [lindex $attrs 3]
			
			SelectObject $coorX $coorY FALSE
			
			# Place a cross.
			try {
				Menu "Edit::Part"
				after 1000
				OrSymbolEditor::execute placeLine 0 0 $symbolWidth $symbolHeight
				OrSymbolEditor::execute setProperty {Line Width} 1
				OrSymbolEditor::execute placeLine $symbolWidth 0 0 $symbolHeight
				OrSymbolEditor::execute setProperty {Line Width} 1
				# Close and save the edit symbol page.
				MenuCommand "57927" OrSymbolEditor::execute save 0 | DialogBox  "15443" "//Save_Part_Instance.xml"
				Menu "File::Save"
				after 1000
				
				# Set the symbol color to red.
				SelectObject $coorX $coorY FALSE
				# Edit Properties
				ShowSpreadsheet
				after 1000
				# Set to red twice.
				ModifyProperty "${schFolderName} : ${schPage} : ${partRef}"  "Color" "RGB(255,  0,  0)" 0
				ModifyProperty "${schFolderName} : ${schPage} : ${partRef}"  "Color" "RGB(255,  0,  0)" 0
				# Apply
				MenuCommand "17146"
				MenuCommand "57927"
				after 1000
				
				# Make NI not display.
				DoNotDisplayNI
				Menu "File::Save"
				after 1000
			} on error {errMsg} {
				# Just keep the part reference if meet any exception.
				puts "Exception occurred: $errMsg"
				lappend uncrossedPart $partRef
				continue
			}
		}
		MenuCommand "57927"
		# Add waiting time to next page.
		after 2000
	}
	
	SelectPMItem $schFolderName
	Menu "File::Save As" | FileDialog  "OK" "${dsnDirName}/${dsnPureName}_cross/${dsnName}" 1
	Menu "File::close"
	Menu "File::Exit"
	
	if {[llength $uncrossedPart] ne 0} {
		# Export all part references that are not crossed.
		set writeFileHandle [open "${dsnDirName}/${dsnPureName}_cross/UncrossedPartRef.txt" w]
		puts -nonewline $writeFileHandle $uncrossedPart
		close $writeFileHandle
	}
}

#========== Method ==========
proc EDFCleaning {edfFilePath} {
	# Only get the data we may need by prefix text.
	set startWordsKeep {"(page" "(rename " "(stringDisplay " "(cellRef " "(rectangle" "(pt " "(transform" "(orientation "}
	set startWordsThrow {"(rename OUTER" "(rename INNER" "(rename HORIZON" "(rename VERTICAL" "(rename BORDER" "(rename DESIGN" "(rename ECOLOGY" "(rename APPROVED" "(rename MANUFACTURER"}
	set filterEDF {}
	set fileHandle [open $edfFilePath r]
	while {[gets $fileHandle line] >= 0} {
		# Read EDF line-by-line.
		set removeLeftSpace [string trimleft $line]
		set matchKeep [startsWithAnyPrefix $removeLeftSpace $startWordsKeep]
		set matchThrow [startsWithAnyPrefix $removeLeftSpace $startWordsThrow]
		if {$matchKeep eq 1 && $matchThrow eq 0} {
			lappend filterEDF [string trim $line]
		}
	}
	close $fileHandle
	
	return $filterEDF
}

proc startsWithAnyPrefix {str prefixes} {
	# Check whether the str starts with the prefixes or not.
    foreach prefix $prefixes {
        if {[string first $prefix $str] == 0} {
            return 1
        }
    }
    return 0
}

proc GetSchematicFolderName {filterEDFList} {
	# Get schematic folder name inside the OrCAD file hierarchy.
	set length [llength $filterEDFList]
	
	for {set i 0} {$i < $length} {incr i} {
		set rowData [lindex $filterEDFList $i]
		if {[string first "(rename SCHEMATIC1" $rowData] == 0} {
			set splitRowData [split [string trim $rowData] " "]
			# Remove " & ) for the folder name.
			set folderName [string map {"\"" "" ")" ""} [lindex $splitRowData 2]]
			return $folderName
		}
	}
	return "SCHEMATIC1"
}

proc GetSchematicPage {filterEDFList partRef} {
	# Get the page text for the target part reference.
	set length [llength $filterEDFList]
	
	# Get the part reference string index from rear side.
	set partRefIndex -1
	for {set i 0} {$i < $length} {incr i} {
		if {[lindex $filterEDFList $i] eq "(stringDisplay \"$partRef\""} {
			set formerRow [lindex $filterEDFList [expr $i - 1]]
			if {[string first "(cellRef " $formerRow] == 0} {
				set partRefIndex $i
				break
			}
		}
	}
	
	# Search backward from the part reference index to find the page name.
	if {$partRefIndex ne -1} {
		for {set pridx $partRefIndex} {$pridx >= 0} {incr pridx -1} {
			if {[lindex $filterEDFList $pridx] eq "(page"} {
				# The next line for the "(page" seems to be the page name.
				set nextLine [lindex $filterEDFList [expr {$pridx + 1}]]
				# Use reX to extract the string in the "".
				if {[regexp {"(.*?)"} $nextLine match group]} {
					return $group
				}
			}
		}
		return ""
	} else {
		error "Can't find ${partRef} in the EDF file."
	}
}

proc GetSymbolCoordinates {filterEDFList partRef} {
	# Get coordinates under "(transform".
	set length [llength $filterEDFList]
	
	# Get the part reference string index from rear side.
	set partRefIndex -1
	for {set i 0} {$i < $length} {incr i} {
		if {[lindex $filterEDFList $i] eq "(stringDisplay \"$partRef\""} {
			set formerRow [lindex $filterEDFList [expr $i - 1]]
			if {[string first "(cellRef " $formerRow] == 0} {
				set partRefIndex $i
				break
			}
		}
	}
	
	# Search down to get the coordinates.
	for {set pridx $partRefIndex} {$pridx < $length} {incr pridx} {
		set rowData [lindex $filterEDFList $pridx]
		if {$rowData eq "(transform"} {
			# Get symbol coordinates.
			set nextLine [lindex $filterEDFList [expr $pridx + 1]]
			if {[string first "(ori" $nextLine] == 0} {
				# Processing rotating symbol.
				set coorLine [lindex $filterEDFList [expr {$pridx + 2}]]
				set splitCoor [split [string trim $coorLine] " "]
				set coorX [format {%0.2f} [expr [string map {"-" ""} [lindex $splitCoor 1]] / 100.00]]
				set coorY [format {%0.2f} [expr [string map {"-" "" ")" ""} [lindex $splitCoor 2]] / 100.00]]
				set coorY [format {%0.2f} [expr $coorY - 0.15]]
				set coor [list $coorX $coorY]
				
				return $coor
			} else {
				# Processing normal symbol.
				set splitCoor [split [string trim $nextLine] " "]
				set coorX [format {%0.2f} [expr [string map {"-" ""} [lindex $splitCoor 1]] / 100.00]]
				set coorY [format {%0.2f} [expr [string map {"-" "" ")" ""} [lindex $splitCoor 2]] / 100.00]]
				set coorX [format {%0.2f} [expr $coorX + 0.05]]
				set coor [list $coorX $coorY]
				
				return $coor
			}
		}
	}
}

proc GetSymbolSize {filterEDFList partRef} {
	# Get symbol width and height.
	set length [llength $filterEDFList]
	
	# Get the part reference string index from rear side.
	set partRefIndex -1
	for {set i 0} {$i < $length} {incr i} {
		if {[lindex $filterEDFList $i] eq "(stringDisplay \"$partRef\""} {
			set formerRow [lindex $filterEDFList [expr $i - 1]]
			if {[string first "(cellRef " $formerRow] == 0} {
				set partRefIndex $i
				break
			}
		}
	}
	
	# Search backward to get the cellRef value.
	set cellRefText -1
	set cellRefFindFlag 1
	set renameCellRefIndex -1
	if {$partRefIndex ne -1} {
		for {set edfRowIdx $partRefIndex} {$edfRowIdx >= 0} {incr edfRowIdx -1} {
			set rowData [lindex $filterEDFList $edfRowIdx]
			if {[string first "(cellRef " $rowData] == 0 && $cellRefFindFlag == 1} {
				set cellRefSplit [split [string trim $rowData] " "]
				set cellRefText [lindex $cellRefSplit 1]
				set cellRefFindFlag 0
			}
			if {[string first "(rename ${cellRefText} " $rowData] == 0 && $cellRefFindFlag == 0} {
				set renameCellRefIndex $edfRowIdx
				break
			}
		}
	} else {
		error "Can't find ${partRef} in the EDF file."
	}
	
	# Then search down for symbol size.
	# TODO: Search the next "(library" index and check if the "(rectangle" index larger than it.
	# If does, it means the cellRef we are searching has no size to obtain, set as 0.2 0.1
	for {set cellRefIdx $renameCellRefIndex} {$cellRefIdx < $length} {incr cellRefIdx} {
		set rowData [lindex $filterEDFList $cellRefIdx]
		if {$rowData eq "(rectangle"} {
			set nextLine [lindex $filterEDFList [expr {$cellRefIdx + 1}]]
			set next2Line [lindex $filterEDFList [expr {$cellRefIdx + 2}]]
			set splitHeight [split [string trim $nextLine] " "]
			set splitWidth [split [string trim $next2Line] " "]
			set symbolWidth [format {%0.2f} [expr [string map {"-" "" ")" ""} [lindex $splitWidth 1]] / 100.00]]
			set symbolHeight [format {%0.2f} [expr [string map {"-" "" ")" ""} [lindex $splitHeight 2]] / 100.00]]
			
			return [list $symbolWidth $symbolHeight]
		}
	}
}

proc DoNotDisplayNI {} {
	# Making POP Property Invisible.
	set lStatus [DboState]
	set lCStr [DboTclHelper_sMakeCString]
	# Set target property as "POP".
	set lPropName [DboTclHelper_sMakeCString "POP"]
	set pLocation [DboTclHelper_sMakeCPoint 0 0]
	# Set font attributes.
	set pFont [DboTclHelper_sMakeLOGFONT "Arial" 12 0 0 0 400 0 0 0 0 7 0 1 16]
	set lPage [GetActivePage]
	set lSelectedObjectsList [GetSelectedObjects] 
	foreach lObj $lSelectedObjectsList {
		$lObj GetTypeString $lCStr
		set lObjTypeStr [DboTclHelper_sGetConstCharPtr $lCStr]
		if { $lObjTypeStr == "Placed Instance" } {
			set lDispProp [$lObj GetDisplayProp $lPropName $lStatus]
			$lObj DeleteDisplayProp $lDispProp
		}
	}
	UnSelectAll
	catch {Menu View::Zoom::Redraw}
}
