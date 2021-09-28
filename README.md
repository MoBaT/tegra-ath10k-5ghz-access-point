# tegra-ath10k-5ghz-access-point

## Hardware Requirements
- Jetson AGX/NX
- Kernel 4.9
- [SX-PCEAC2-M2-SP Wifi Chip](https://www.mouser.com/ProductDetail/Silex-Technology/SX-PCEAC2-M2-SP?qs=CiayqK2gdcJfCb2Jvfe5kA%3D%3D&mgh=1&gclid=CjwKCAjw7rWKBhAtEiwAJ3CWLOzo2LLmCA6jMi9mLQ0Ql8lo1lGqHbRJEegoUeMXnzNuusOj5jt86BoCf_8QAvD_BwE)

## How to Use
1. Modify `hostapd.conf` file to your liking (SSID, password, etc)
2. Copy modified `hostapd.conf` to `/etc/hostapd/hostapd.conf` (Will switch you to AP mode)
3. Add static IP for `wlan0` in `/etc/network/interfaces` (To switch from being a client to hostspot)
    ```
    auto wlan0
    iface wlan0 inet static
      address 10.10.0.1
      netmask 255.255.255.0
    ```
4. Ensure `hostapd` and `dnsmasq` services are enabled and running 
5. Run `sudo ./run.sh` to patch and build kernel modules ATH + ATH10k (This will put the domain to US. Modify the run.sh to change)
6. Reboot and check `sudo iw list` to make sure all the `NO-IR` on the 5GHZ frequencies are gone!
