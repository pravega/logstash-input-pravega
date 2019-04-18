## 0.4.0
 - Switch the version of pravega-client API to 0.4.0
  - Fix some bugs of the old version
      - Add the argument precheck for input plugin
      - The input format should be plain text not json
  - Create only one readerGroup
  - Add config.xml for constants configuration
  - Make the reader_threads become constant configed in the config.xml
  - Add username and password for controller authorization
  - Delete unused import and some config arguments

## 0.1.0
  - Plugin created with the logstash plugin generator
