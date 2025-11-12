package main

import goxash3d_fwgs "github.com/jklenner/goxash3d-fwgs/pkg"

func main() {
	goxash3d_fwgs.DefaultXash3D.Net = net

	go runSFU()

	goxash3d_fwgs.DefaultXash3D.SysStart()
}
