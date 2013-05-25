# required parameters :
#       $buildNumber

Framework "4.0"

properties {
    # build properties - change as needed
    $baseDir = resolve-path .\..
    $sourceDir = "$baseDir\src"
    $buildDir = "$baseDir\build"
    # change as needed, TestResults is used by TeamCity
    $testDir = "$buildDir\TestResults"
    $packageDir = "$buildDir\package"
    
    $companyName = "yourCompany"
    $projectName = "projectName"
    $projectConfig = "Release"
    $unitTestProject = "$projectName.Tests"
    $unitTestAssembly = "$sourceDir\$unitTestProject\bin\$projectConfig\$unitTestProject.dll"

    # if not provided, default to 1.0.0.0
    if(!$version)
    {
        $version = "1.0.0.0"
    }

    # tools
    # change testExecutable as needed, defaults to mstest
    $testExecutable = "C:\Program Files (x86)\Microsoft Visual Studio 11.0\Common7\IDE\mstest.exe"
    $nuget = "$sourceDir\packages\NuGet.CommandLine.2.5.0\tools\NuGet.exe"

    # if not provided, default to Dev
    if (!$nuGetSuffix)
    {
        $nuGetSuffix = "Dev"
    }

    # source locations
    $projectSourceDir = "$sourceDir\$projectName\"

    # package locations
    $projectPackageDir = "$packageDir\$projectName\"

    # nuspec files
    $projectNuspec = "$projectPackageDir\$projectName.nuspec"
    $projectNuspecTitle = "$projectName title"
    $projectNuspecDescription = "$projectName description"

    # deploy scripts
    $projectDeployFile = "$buildDir\Deploy-$projectName.ps1"
}

task default -depends UnitTest, PackageNuGet

# Initialize the build, delete any existing package or test folders
task Init {
    Write-Host "Deleting the package directory"
    DeleteFile $packageDir
    Write-Host "Deleting the test directory"
    DeleteFile $testDir
}

# Compile the Project solution and any other solutions necessary
task Compile -depends Init {
    Write-Host "Cleaning the solution"
    exec { msbuild /t:clean /v:q /nologo /p:Configuration=$projectConfig $sourceDir\$projectName.sln }
    DeleteFile $error_dir
    Write-Host "Building the solution"
    exec { msbuild /t:build /v:q /nologo /p:Configuration=$projectConfig $sourceDir\$projectName.sln }
}

# Execute unit tests
# Change as necessary if using a different test tool
task UnitTest -depends Compile {
    exec { & $testExecutable /testcontainer:$unitTestAssembly | Out-Null }
}

# TODO
# Create a common assembly info file to be shared by all projects with the provided version number
task CommonAssemblyInfo {
    $version = "1.0.0.0"   
    CreateCommonAssemblyInfo "$version" $projectName "$source_dir\CommonAssemblyInfo.cs"
}

# Package the project web code
# Copy only the necessary files, exclude .cs files
task PackageProject -depends Compile {
    Write-Host "Packaging $projectName"
    CopyWebSiteFiles $projectSourceDir "$projectPackageDir\content\"

    # deploy.ps1 is used by Octopus Deploy
    Write-Host "Copying $projectDeployFile to $projectPackageDir\Deploy.ps1"
    cp $projectDeployFile "$projectPackageDir\Deploy.ps1"
    
    attrib -r "$projectPackageDir\*.*" /S /D
}

# The Package task depends on all other package tasks
# Template only includes one package task (PackageProject).
# If you need to package multiple solutions, add them as dependencies for Package
task Package -depends PackageProject { #, PackageApiProject, PackageDatabase {
}

# PackageNuGet creates the NuGet packages for each package needed to deploy the solution
task PackageNuGet -depends Package {    
    Write-Host "Create $projectName nuget manifest"
    CreateNuGetManifest $version $projectName $projectNuspec $projectNuspecTitle $projectNuspecDescription
    Write-Host "Package $projectNuspec with base path $projectPackageDir and package dir $packageDir"
    exec { & $nuget pack $projectNuspec -OutputDirectory $packageDir }
}

# Deploy the JOReportingService locally
task DeployProject -depends PackageProject {
    cd $projectPackageDir
    & ".\Deploy.ps1"
    cd $baseDir
}

# ------------------------------------------------------------------------------------#
# Utility methods
# ------------------------------------------------------------------------------------#

# Copy files needed for a website, ignore source files and other unneeded files
function global:CopyWebSiteFiles($source, $destination){
    $exclude = @('*.user', '*.dtd', '*.tt', '*.cs', '*.csproj', '*.orig', '*.log')
    CopyFiles $source $destination $exclude
    DeleteDirectory "$destination\obj"
}

# copy files to a destination
# create the directory if it does not exist
function global:CopyFiles($source, $destination, $exclude = @()){    
    CreateDirectory $destination
    Get-ChildItem $source -Recurse -Exclude $exclude | Copy-Item -Destination { Join-Path $destination $_.FullName.Substring($source.length); }
}

# Create a directory
function global:CreateDirectory($directoryName)
{
    mkdir $directoryName -ErrorAction SilentlyContinue | Out-Null
}

# Delete a directory
function global:DeleteDirectory($directory_name)
{
    rd $directory_name -recurse -force -ErrorAction SilentlyContinue | Out-Null
}

# Delete a file if it exists
function global:DeleteFile($file) {
    if ($file)
    {
        Remove-Item $file -force -recurse -ErrorAction SilentlyContinue | Out-Null
    }
}

# Create a NuGet manifest file
function global:CreateNuGetManifest($version, $applicationName, $filename, $title, $description)
{
"<?xml version=""1.0""?>
<package xmlns=""http://schemas.microsoft.com/packaging/2010/07/nuspec.xsd"">
  <metadata>
    <id>$companyName.$applicationName.$nuGetSuffix</id>
    <title>$title</title>
    <version>$version</version>
    <authors>$companyName</authors>
    <owners>$companyName</owners>
    <licenseUrl>http://www.$applicationName.com</licenseUrl>
    <projectUrl>http://www.$applicationName.com</projectUrl>
    <iconUrl>http://www.$applicationName.com</iconUrl>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <description>$description</description>
    <summary>$description</summary>
    <language>en-US</language>
  </metadata>
</package>" | Out-File $filename -encoding "ASCII"
}

# Create a CommonAssemblyInfo file
function global:CreateCommonAssemblyInfo($version, $applicationName, $filename)
{
"using System;
using System.Reflection;
using System.Runtime.InteropServices;

//------------------------------------------------------------------------------
// <auto-generated>
//     This code was generated by a tool.
//     Runtime Version:2.0.50727.4927
//
//     Changes to this file may cause incorrect behavior and will be lost if
//     the code is regenerated.
// </auto-generated>
//------------------------------------------------------------------------------

[assembly: ComVisibleAttribute(false)]
[assembly: AssemblyVersionAttribute(""$version"")]
[assembly: AssemblyFileVersionAttribute(""$version"")]
[assembly: AssemblyCopyrightAttribute(""Copyright 2010"")]
[assembly: AssemblyProductAttribute(""$applicationName"")]
[assembly: AssemblyCompanyAttribute(""Headspring"")]
[assembly: AssemblyConfigurationAttribute(""release"")]
[assembly: AssemblyInformationalVersionAttribute(""$version"")]"  | Out-File $filename -encoding "ASCII"    
}