from setuptools import setup

setup(name='plexos2pras',
      version='0.2.0',
      packages=['plexos2pras'],
      package_data={'plexos2pras': ['*.jl']},
      entry_points={
          'console_scripts': [
              'process-workbook = plexos2pras.process_workbook:_process_workbook',
              'process-solutions = plexos2pras.process_solutions:_process_solutions',
          ]
      },
      )
