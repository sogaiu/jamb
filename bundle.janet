# adapted from jeep and spork/path

(def- my/w32-grammar
  ~{:main (sequence (opt (sequence (replace (capture :lead)
                                            ,(fn [& xs]
                                               [:lead (get xs 0)]))
                                   (any (set `\/`))))
                    (opt (capture :span))
                    (any (sequence :sep (capture :span)))
                    (opt (sequence :sep (constant ""))))
    :lead (sequence (opt (sequence :a `:`)) `\`)
    :span (some (if-not (set `\/`) 1))
    :sep (some (set `\/`))})

(def- my/posix-grammar
  ~{:main (sequence (opt (sequence (replace (capture :lead)
                                            ,(fn [& xs]
                                               [:lead (get xs 0)]))
                                   (any "/")))
                    (opt (capture :span))
                    (any (sequence :sep (capture :span)))
                    (opt (sequence :sep (constant ""))))
    :lead "/"
    :span (some (if-not "/" 1))
    :sep (some "/")})

(defn- my/normalize
  [path &opt doze?]
  (default doze? (= :windows (os/which)))
  (def accum @[])
  (def parts
    (peg/match (if doze?
                 my/w32-grammar
                 my/posix-grammar)
               path))
  (var seen 0)
  (var lead nil)
  (each x parts
    (match x
      [:lead what] (set lead what)
      #
      "." nil
      #
      ".."
      (if (zero? seen)
        (array/push accum x)
        (do
          (-- seen)
          (array/pop accum)))
      #
      (do
        (++ seen)
        (array/push accum x))))
  (def ret
    (string (or lead "")
            (string/join accum (if doze? `\` "/"))))
  #
  (if (empty? ret)
    "."
    ret))

(defn- my/join
  [& els]
  (def end (last els))
  (when (and (one? (length els))
             (not (string? end)))
    (error "when els only has a single element, it must be a string"))
  #
  (def [items sep]
    (cond
      (true? end)
      [(slice els 0 -2) `\`]
      #
      (false? end)
      [(slice els 0 -2) "/"]
      #
      [els (if (= :windows (os/which)) `\` "/")]))
  #
  (my/normalize (string/join items sep)))

(defn my/abspath?
  [path &opt doze?]
  (default doze? (= :windows (os/which)))
  (if doze?
    # https://stackoverflow.com/a/23968430
    # https://learn.microsoft.com/en-us/dotnet/standard/io/file-path-formats
    (truthy? (peg/match ~(sequence :a `:\`) path))
    (string/has-prefix? "/" path)))

(defn- my/abspath
  [path &opt doze?]
  (default doze? (= :windows (os/which)))
  (if (my/abspath? path doze?)
    (my/normalize path doze?)
    # dynamic variable useful for testing
    (my/join (or (dyn :localpath-cwd) (os/cwd))
             path
             doze?)))

# XXX: not so tested
(defn- my/basename
  [path &opt doze?]
  (def tos (= :windows (os/which)))
  (default doze? tos)
  (def revpath (string/reverse path))
  (def s (if tos `\` "/"))
  (def i (string/find s revpath))
  (if i
    (-> (string/slice revpath 0 i)
        string/reverse)
    path))

########################################################################

(defn- my/get-os-stuff
  []
  (def seps {:windows `\` :mingw `\` :cygwin `\`})
  (def tos (os/which))
  [tos (get seps tos "/")])

(defn- my/add-manpages
  [manifest s]
  (def manpages (get-in manifest [:info :manpages] []))
  (os/mkdir (string (dyn :syspath) s "man"))
  (os/mkdir (string (dyn :syspath) s "man" s "man1"))
  (each mp manpages
    (bundle/add-file manifest mp)))

(defn- my/add-sources
  [manifest s]
  (each src (get-in manifest [:info :sources])
    (def {:prefix prefix
          :items items} src)
    (bundle/add-directory manifest prefix)
    (each i items
      (bundle/add manifest i (string prefix s i)))))

(defn- my/add-binscripts
  [manifest [tos s]]
  (each binscript (get-in manifest [:info :binscripts] [])
    (def {:main main
          :hardcode-syspath hardcode-syspath
          :is-janet is-janet} binscript)
    (def main (my/abspath main))
    (def bin-name (my/basename main))
    (def dest (my/join "bin" bin-name))
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
      (def absdest (my/join (dyn *syspath*) dest))
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

########################################################################

(defn install [manifest &]
  (def [tos s] (my/get-os-stuff))
  #
  (my/add-manpages manifest s)
  #
  (my/add-sources manifest s)
  #
  (my/add-binscripts manifest [tos s]))

