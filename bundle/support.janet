# adapted from jeep and spork
(import ./mypath :as path)

(defn get-os-stuff
  []
  (def seps {:windows `\` :mingw `\` :cygwin `\`})
  (def tos (os/which))
  [tos (get seps tos "/")])

(defn add-manpages
  [manifest s]
  (def manpages (get-in manifest [:info :manpages] []))
  (os/mkdir (string (dyn :syspath) s "man"))
  (os/mkdir (string (dyn :syspath) s "man" s "man1"))
  (each mp manpages
    (bundle/add-file manifest mp)))

(defn add-sources
  [manifest s]
  (each src (get-in manifest [:info :sources])
    (def {:prefix prefix
          :items items} src)
    (bundle/add-directory manifest prefix)
    (each i items
      (bundle/add manifest i (string prefix s i)))))

(defn add-binscripts
  [manifest [tos s]]
  (each binscript (get-in manifest [:info :binscripts] [])
    (def {:main main
          :hardcode-syspath hardcode-syspath
          :is-janet is-janet} binscript)
    (def main (path/abspath main))
    (def bin-name (path/basename main))
    (def dest (path/join "bin" bin-name))
    (def contents
      (with [f (file/open main :rbn)]
        (def line-1 (:read f :line))
        (def auto-shebang
          (and is-janet (not (string/has-prefix? "#!" line-1))))
        (def dynamic-syspath (= hardcode-syspath :dynamic))
        (def line-2
          (string "(put root-env :original-syspath "
                  "(os/realpath (dyn *syspath*))) # auto generated\n"))
        (def line-3
          (string/format "(put root-env :syspath %v) # auto generated\n"
                         (dyn *syspath*)))
        (def line-4
          (string/format "(put root-env :install-time-syspath %v) %s\n"
                         (dyn *syspath*)
                         "# auto generated"))
        (def rest (:read f :all))
        (string (if auto-shebang (string "#!/usr/bin/env janet\n"))
                line-1
                (if (or dynamic-syspath hardcode-syspath) line-2)
                (if hardcode-syspath line-3)
                (if hardcode-syspath line-4)
                rest)))
    (def bin-temp (string bin-name ".temp"))
    # XXX: want bundle/add-buffer so this temp file would be unneeded...
    (defer (os/rm bin-temp)
      (spit bin-temp contents)
      (bundle/add-bin manifest bin-temp bin-name))
    (when (or (= :windows tos) (= :mingw tos))
      (def absdest (path/join (dyn *syspath*) dest))
      # jpm and janet-pm have bits like this
      # https://github.com/microsoft/terminal/issues/217#issuecomment-737594785
      (def bat-content
        (string "@echo off\r\n"
                "goto #_undefined_# 2>NUL || "
                `title %COMSPEC% & janet "` absdest `" %*`))
      (def bat-name (string main ".bat"))
      # XXX: want bundle/add-buffer so this temp file would be unneeded...
      (defer (os/rm bat-name)
        (spit bat-name bat-content)
        (bundle/add-bin manifest bat-name)))))

