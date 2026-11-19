-- CreateEnum
CREATE TYPE "ForecastState" AS ENUM ('OPEN', 'CLOSED', 'EXPIRED');

-- AlterTable
ALTER TABLE "Recurrence" ADD COLUMN     "isForecast" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "Transaction" ADD COLUMN     "forecastId" TEXT,
ADD COLUMN     "forecastState" "ForecastState",
ADD COLUMN     "isForecast" BOOLEAN NOT NULL DEFAULT false;

-- CreateIndex
CREATE INDEX "Transaction_forecastId_idx" ON "Transaction"("forecastId");

-- CreateIndex
CREATE INDEX "Transaction_userId_isForecast_idx" ON "Transaction"("userId", "isForecast");

-- AddForeignKey
ALTER TABLE "Transaction" ADD CONSTRAINT "Transaction_forecastId_fkey" FOREIGN KEY ("forecastId") REFERENCES "Transaction"("id") ON DELETE SET NULL ON UPDATE CASCADE;
