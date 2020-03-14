module IOTA
  module API
    class Api
      include Wrappers
      include Transport

      attr_reader :pow_provider

      def initialize(broker, sandbox, batch_size = 500, local_pow = false)
        @broker = broker
        @sandbox = sandbox
        @commands = Commands.new
        @utils = IOTA::Utils::Utils.new
        @validator = @utils.validator
        @batch_size = batch_size
        @pow_provider = local_pow ? IOTA::Crypto::PowProvider.new : nil
      end

      def findTransactions(searchValues, &callback)
        if !@validator.isObject(searchValues)
          return sendData(false, "You have provided an invalid key value", &callback)
        end

        searchKeys = searchValues.keys
        validKeys = ['bundles', 'addresses', 'tags', 'approvees']

        error = false
        entry_count = 0

        searchKeys.each do |key|
          if !validKeys.include?(key.to_s)
            error = "You have provided an invalid key value"
            break
          end

          hashes = searchValues[key]
          entry_count += hashes.count

          if key.to_s == 'addresses'
            searchValues[key] = hashes.map do |address|
              @utils.noChecksum(address)
            end
          end

          # If tags, append to 27 trytes
          if key.to_s == 'tags'
            searchValues[key] = hashes.map do |hash|
              # Simple padding to 27 trytes
              while hash.length < 27
                hash += '9'
              end
              # validate hash
              if !@validator.isTrytes(hash, 27)
                error = "Invalid Trytes provided"
                break
              end

              hash
            end
          else
            # Check if correct array of hashes
            if !@validator.isArrayOfHashes(hashes)
              error = "Invalid Trytes provided"
              break
            end
          end
        end

        if error
          return sendData(false, error, &callback)
        else
          if entry_count <= @batch_size || searchKeys.count > 1
            return sendCommand(@commands.findTransactions(searchValues), &callback)
          else
            return sendBatchedCommand(@commands.findTransactions(searchValues), &callback)
          end
        end
      end

      def getBalances(addresses, threshold, &callback)
        if !@validator.isArrayOfHashes(addresses)
          return sendData(false, "Invalid Trytes provided", &callback)
        end

        command = @commands.getBalances(addresses.map{|address| @utils.noChecksum(address)}, threshold)
        sendBatchedCommand(command, &callback)
      end

      def getTrytes(hashes, &callback)
        if !@validator.isArrayOfHashes(hashes)
          return sendData(false, "Invalid Trytes provided", &callback)
        end

        sendBatchedCommand(@commands.getTrytes(hashes), &callback)
      end

      def getInclusionStates(transactions, tips, &callback)
        if !@validator.isArrayOfHashes(transactions) || !@validator.isArrayOfHashes(tips)
          return sendData(false, "Invalid Trytes provided", &callback)
        end

        sendBatchedCommand(@commands.getInclusionStates(transactions, tips), &callback)
      end

      def getNodeInfo(&callback)
        sendCommand(@commands.getNodeInfo, &callback)
      end

      def getNeighbors(&callback)
        sendCommand(@commands.getNeighbors, &callback)
      end

      def addNeighbors(uris, &callback)
        (0...uris.length).step(1) do |i|
          return sendData(false, "You have provided an invalid URI for your Neighbor: " + uris[i], &callback) if !@validator.isUri(uris[i])
        end

        sendCommand(@commands.addNeighbors(uris), &callback)
      end

      def removeNeighbors(uris, &callback)
        (0...uris.length).step(1) do |i|
          return sendData(false, "You have provided an invalid URI for your Neighbor: " + uris[i], &callback) if !@validator.isUri(uris[i])
        end

        sendCommand(@commands.removeNeighbors(uris), &callback)
      end

      def getTips(&callback)
        sendCommand(@commands.getTips, &callback)
      end

      def getTransactionsToApprove(depth, reference = nil, &callback)
        # Check if correct depth
        if !@validator.isValue(depth)
          return sendData(false, "Invalid inputs provided", &callback)
        end

        sendCommand(@commands.getTransactionsToApprove(depth, reference), &callback)
      end

      def attachToTangle(trunkTransaction, branchTransaction, minWeightMagnitude, trytes, &callback)
        # Check if correct trunk
        if !@validator.isHash(trunkTransaction)
          return sendData(false, "You have provided an invalid hash as a trunk: #{trunkTransaction}", &callback)
        end

        # Check if correct branch
        if !@validator.isHash(branchTransaction)
          return sendData(false, "You have provided an invalid hash as a branch: #{branchTransaction}", &callback)
        end

        # Check if minweight is integer
        if !@validator.isValue(minWeightMagnitude)
          return sendData(false, "Invalid minWeightMagnitude provided", &callback)
        end

        # Check if array of trytes
        if !@validator.isArrayOfTrytes(trytes)
          return sendData(false, "Invalid Trytes provided", &callback)
        end

        if @pow_provider.nil?
          command = @commands.attachToTangle(trunkTransaction, branchTransaction, minWeightMagnitude, trytes)

          sendCommand(command, &callback)
        else
          previousTxHash = nil
          finalBundleTrytes = []

          trytes.each do |current_trytes|
            txObject = @utils.transactionObject(current_trytes)

            if !previousTxHash
              if txObject.lastIndex != txObject.currentIndex
                return sendData(false, "Wrong bundle order. The bundle should be ordered in descending order from currentIndex", &callback)
              end

              txObject.trunkTransaction = trunkTransaction
              txObject.branchTransaction = branchTransaction
            else
              txObject.trunkTransaction = previousTxHash
              txObject.branchTransaction = trunkTransaction
            end

            txObject.attachmentTimestamp = (Time.now.to_f * 1000).to_i
            txObject.attachmentTimestampLowerBound = 0
            txObject.attachmentTimestampUpperBound = (3**27 - 1) / 2

            newTrytes = @utils.transactionTrytes(txObject)

            begin
              returnedTrytes = @pow_provider.pow(newTrytes, minWeightMagnitude)

              newTxObject= @utils.transactionObject(returnedTrytes)
              previousTxHash = newTxObject.hash

              finalBundleTrytes << returnedTrytes
            rescue => e
              return sendData(false, e.message, &callback)
            end
          end

          sendData(true, finalBundleTrytes, &callback)
        end
      end

      def interruptAttachingToTangle(&callback)
        sendCommand(@commands.interruptAttachingToTangle, &callback)
      end

      def broadcastTransactions(trytes, &callback)
        if !@validator.isArrayOfAttachedTrytes(trytes)
          return sendData(false, "Invalid attached Trytes provided", &callback)
        end

        sendCommand(@commands.broadcastTransactions(trytes), &callback)
      end

      def storeTransactions(trytes, &callback)
        if !@validator.isArrayOfAttachedTrytes(trytes)
          return sendData(false, "Invalid attached Trytes provided", &callback)
        end

        sendCommand(@commands.storeTransactions(trytes), &callback)
      end

      def checkConsistency(tails, &callback)
        if !@validator.isArrayOfHashes(tails)
          return sendData(false, "Invalid tails provided", &callback)
        end

        sendCommand(@commands.checkConsistency(tails), &callback)
      end

      def wereAddressesSpentFrom(addresses, &callback)
        if !@validator.isArrayOfHashes(addresses)
          return sendData(false, "Invalid Trytes provided", &callback)
        end

        command = @commands.wereAddressesSpentFrom(addresses.map{|address| @utils.noChecksum(address)})
        sendBatchedCommand(command, &callback)
      end

      def getNodeAPIConfiguration(&callback)
        sendCommand(@commands.getNodeAPIConfiguration, &callback)
      end

      def getMissingTransactions(&callback)
        sendCommand(@commands.getMissingTransactions, &callback)
      end

      private
      def sendData(status, data, &callback)
        callback ? callback.call(status, data) : [status, data]
      end
    end
  end
end
