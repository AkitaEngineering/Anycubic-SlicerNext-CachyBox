# MIT License

Copyright (c) 2026 Sascha Schüller
Copyright (c) 2026 Akita Engineering

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## Fork Notice

This repository began with the original MIT-licensed work by Sascha Schüller.
Akita Engineering later adapted that work for a containerized slicer workflow.
This fork retargets the automation for Anycubic Slicer Next while keeping the
repository-side scripts and container definitions under the MIT terms above.

Any redistribution of this repository must retain the MIT copyright notice and
permission notice above.

---

## Disclaimer Regarding Anycubic Slicer Next

The MIT license above applies only to the automation and packaging material in
this repository, including the installer and uninstaller scripts, the compose
file, the entrypoint helpers, and the container definitions.

Please note:

* Anycubic Slicer Next is developed and published by ANYCUBIC-3D and released under AGPL-3.0.
* This project does not bundle Anycubic Slicer Next binaries. It automates cloning the official upstream repository, building the application, generating an AppImage, and integrating that output into a local container workflow.
* By using these scripts, you are responsible for complying with the upstream Anycubic Slicer Next license terms.
* The developers of this project are not affiliated with ANYCUBIC-3D.