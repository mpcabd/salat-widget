// The azan recordings bundled with the app.
//
// To add a recording:
//   1. Put the audio file (mp3, m4a, wav…) in Resources/Audio/.
//   2. Add an entry to `recordings` below. Pass `fajr: true` for a Fajr azan
//      (with “الصلاة خير من النوم”); it's then offered only in the Fajr picker.
//   3. Add it to Credits in README.md.
//
// The pickers list recordings in this order. `swift test` checks that IDs are unique,
// that every file exists, and that the defaults point at real recordings.
//
// Keep an ID once it has shipped: it's what users' settings store. If you remove a
// recording, anyone who picked it falls back to the default.

enum AzanCatalog {
    static let defaultID = "hamza-moaz"
    static let defaultFajrID = "alafasy-fajr-saikah"

    static let recordings: [AzanSound] = [
        AzanSound(id: "hamza-moaz",
                  nameEN: "Hamza Moaz", nameAR: "حمزة معاذ",
                  file: "hamza-moaz.mp3",
                  credit: "Hamza Moaz", license: "Unknown",
                  source: "https://soundcloud.com/theislamicsound/beautiful-azan-by-qari-hamza-maaz"),
        AzanSound(id: "alafasy-fajr-saikah",
                  nameEN: "Alafasy Al Fajr Saikah", nameAR: "العفاسي الفجر سيكاه",
                  file: "alafasy-fajr-saikah.mp3",
                  fajr: true,
                  credit: "Mishary Alafasy", license: "Unknown",
                  source: "https://soundcloud.com/alafasy/athanalfajrsaikah"),
    ]
}
