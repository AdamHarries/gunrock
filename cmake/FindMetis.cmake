#
# Find the PARMETIS includes and libraries
#
# ParMETIS is an MPI-based parallel library that implements a variety of algorithms for
# partitioning unstructured graphs, meshes, and for computing fill-reducing orderings of
# sparse matrices. It can be found at:
# http://www-users.cs.umn.edu/~karypis/metis/parmetis/index.html
#
# PARMETIS_INCLUDE_DIR - where to find autopack.h
# PARMETIS_LIBRARIES   - List of fully qualified libraries to link against.
# PARMETIS_FOUND       - Do not attempt to use if "no" or undefined.

FIND_PATH(PARMETIS_INCLUDE_DIR parmetis.h
  /usr/local/include
  /usr/include
  )

FIND_LIBRARY(PARMETIS_LIBRARY parmetis
  /usr/local/lib
  /usr/lib
  )

IF(PARMETIS_INCLUDE_DIR)
  IF(PARMETIS_LIBRARY)
    SET( PARMETIS_LIBRARIES ${PARMETIS_LIBRARY} ${METIS_LIBRARY})
    SET( PARMETIS_FOUND "YES" )
    ADD_DEFINITIONS( -DPARMETIS_FOUND=true )
    MESSAGE(STATUS "Found ParMetis")
  ENDIF(PARMETIS_LIBRARY)
ENDIF(PARMETIS_INCLUDE_DIR)

# ------------------------------------------------------------------------
#  Gunrock: Find Metis and set pre-compiler flag
# ------------------------------------------------------------------------
FIND_LIBRARY(METIS_LIBRARY metis
  /usr/local/lib
  /usr/lib
  )

SET(gunrock_REQUIRED_METIS_VERSION 5.0)

SET(METIS_FOUND FALSE)
IF (METIS_LIBRARY)
  SET(METIS_FOUND TRUE)
  ADD_DEFINITIONS( -DMETIS_FOUND=true )
  MESSAGE(STATUS "Found Metis")
ELSE (METIS_LIBRARY)
  ADD_DEFINITIONS( -DMETIS_FOUND=false )
  MESSAGE(WARNING "Metis was requested but support was not found,
  run `sudo apt-get install metis` or `/dep/install_metis.sh` for installation.")
ENDIF (METIS_LIBRARY)
