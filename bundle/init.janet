(import ./support :as s)

(defn install [manifest &]
  (def [tos s] (s/get-os-stuff))
  (s/add-manpages manifest s)
  (s/add-sources manifest s)
  (s/add-binscripts manifest [tos s]))

